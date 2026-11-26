// Collect one shared reading-margin frame when its inputs change.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

// fingerprint excludes database bookkeeping and collector output files.
func fingerprint(task, notes, taskrc, probe string, notesCache *string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	format := "#{session_name}\x1f#{window_name}\x1f#{pane_id}\x1f#{pane_pid}\x1f#{pane_current_command}\x1f#{@agent_model}\x1f#{@agent_name}\x1f#{@agent_prs}\x1f#{@agent_resumed}\x1f#{@agent_spawn_level}\x1f#{@agent_spawn_parent}\x1f#{@agent_wait}\x1f#{@claude_state}\x1f#{@claude_state_since}"
	tmux, err := exec.CommandContext(ctx, "tmux", "list-panes", "-a", "-F", format).Output()
	if err != nil {
		return "", err
	}
	h := sha256.New()
	lines := strings.Split(string(tmux), "\n")
	sort.Strings(lines)
	fmt.Fprintf(h, "tmux:%q\n", lines)
	// Consider every pane, even non-agent panes: this is a conservative superset
	// of the renderer's process-backed rows. PR sessions can resolve through notes.
	ids := map[string]bool{}
	idRE := regexp.MustCompile(`(?i)(DEVOPS|DOC|ENGAI|ENGPLAT|IT)-[0-9]+`)
	for _, line := range lines {
		fields := strings.Split(line, "\x1f")
		for _, field := range fields {
			for _, prefix := range []string{"DEVOPS-", "DOC-", "ENGAI-", "ENGPLAT-", "IT-"} {
				if strings.HasPrefix(field, prefix) {
					ids[field] = true
				}
			}
		}
		for _, id := range idRE.FindAllString(line, -1) {
			ids[strings.ToUpper(id)] = true
		}
	}
	// A PR session can resolve to any note with the same PR number. Include
	// all such note keys, covering both the repo match and the fallback match.
	prNumbers := map[string]bool{}
	prSessionRE := regexp.MustCompile(`^.+-pr-?([0-9]+)$`)
	for _, line := range lines {
		fields := strings.Split(line, "\x1f")
		for _, index := range []int{0, 6} {
			if index < len(fields) {
				if m := prSessionRE.FindStringSubmatch(fields[index]); m != nil {
					prNumbers[m[1]] = true
				}
			}
		}
	}
	if len(prNumbers) != 0 {
		prRE := regexp.MustCompile(`(^|\|)\s*pr=[^|]*#([0-9]+)\s*(\||$)`)
		addNote := func(key, value string) {
			for _, m := range prRE.FindAllStringSubmatch(value, -1) {
				if prNumbers[m[2]] {
					ids[key] = true
				}
			}
		}
		entries, err := os.ReadDir(filepath.Join(notes, "cockpit-updates"))
		if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".txt") {
				continue
			}
			data, err := os.ReadFile(filepath.Join(notes, "cockpit-updates", e.Name()))
			if err != nil {
				return "", err
			}
			first, _, _ := strings.Cut(string(data), "\n")
			addNote(strings.TrimSuffix(e.Name(), ".txt"), first)
		}
		data, err := os.ReadFile(filepath.Join(notes, "cockpit-notes.md"))
		if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		for _, line := range strings.Split(string(data), "\n") {
			key, value, ok := strings.Cut(line, ":")
			if ok {
				addNote(strings.TrimSpace(key), value)
			}
		}
	}

	keys := make([]string, 0, len(ids))
	for id := range ids {
		keys = append(keys, id)
	}
	sort.Strings(keys)
	keyJSON, _ := json.Marshal(keys)
	db := filepath.Join(task, "taskchampion.sqlite3")
	if _, err := os.Stat(db); err == nil {
		const py = `import sqlite3,sys,hashlib,json
c=sqlite3.connect('file:'+__import__('urllib.parse',fromlist=['quote']).quote(sys.argv[1])+'?mode=ro',uri=True,timeout=2)
c.execute('BEGIN')
ids=set(json.loads(sys.argv[2])); review=sys.argv[3]=='1'
h=hashlib.sha256()
selected=set()
for uuid,data in c.execute('select uuid,data from tasks order by uuid'):
 d=json.loads(data)
 if not isinstance(d,dict): raise ValueError('unsupported task data')
 if any(x.lower() in str(d.get('linear_issue_id','')).lower() for x in ids) or (review and d.get('status')=='pending' and d.get('linear_issue_id') is not None):
  selected.add(uuid)
  h.update(json.dumps([uuid,data],ensure_ascii=True,separators=(',',':')).encode()); h.update(b'\n')
for row in c.execute('select id,uuid from working_set order by id'):
 if row[1] in selected: h.update(json.dumps(row,separators=(',',':')).encode()); h.update(b'\n')
print(h.hexdigest())
`
		out, err := exec.CommandContext(ctx, "python3", "-c", py, db, string(keyJSON), os.Getenv("COCKPIT_SHOW_REVIEW_ROWS")).Output()
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "sqlite:%s\n", out)
	} else if !os.IsNotExist(err) {
		return "", err
	} else {
		found := false
		for _, name := range []string{"pending.data", "completed.data"} {
			data, err := os.ReadFile(filepath.Join(task, name))
			if err != nil && !os.IsNotExist(err) {
				return "", err
			}
			if err == nil {
				found = true
			}
			fmt.Fprintf(h, "%s:%q\n", name, data)
		}
		if !found {
			return "", fmt.Errorf("unsupported task backend")
		}
	}

	// Task database bookkeeping can trigger frequent checks. Reuse the notes
	// digest until an inotify event or watch-set change invalidates it.
	if *notesCache == "" {
		paths := []string{filepath.Join(notes, "cockpit-notes.md")}
		entries, err := os.ReadDir(notes)
		if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		for _, ent := range entries {
			if ent.Name() != "cockpit-updates" && !strings.HasPrefix(ent.Name(), "cockpit-pr-") {
				continue
			}
			path := filepath.Join(notes, ent.Name())
			if !ent.IsDir() {
				paths = append(paths, path)
				continue
			}
			children, err := os.ReadDir(path)
			if err != nil {
				return "", err
			}
			for _, child := range children {
				name := child.Name()
				if child.IsDir() || strings.HasPrefix(name, ".") || strings.HasSuffix(name, ".try") || strings.HasSuffix(name, ".lock") || strings.Contains(name, ".tmp.") || strings.HasSuffix(name, "-shm") {
					continue
				}
				paths = append(paths, filepath.Join(path, name))
			}
		}
		sort.Strings(paths)
		notesHash := sha256.New()
		for _, path := range paths {
			data, err := os.ReadFile(path)
			if err != nil && !os.IsNotExist(err) {
				return "", err
			}
			fmt.Fprintf(notesHash, "%q:%q\n", path, data)
		}
		*notesCache = fmt.Sprintf("%x", notesHash.Sum(nil))
	}
	fmt.Fprintf(h, "notes:%s\n", *notesCache)
	for _, path := range []string{taskrc, probe} {
		data, err := os.ReadFile(path)
		if err != nil && !os.IsNotExist(err) {
			return "", err
		}
		fmt.Fprintf(h, "%q:%q\n", path, data)
	}
	return fmt.Sprintf("%x", h.Sum(nil)), nil
}

func main() {
	if len(os.Args) < 5 || os.Args[1] != "--state-dir" || os.Args[3] != "--" {
		fmt.Fprintln(os.Stderr, "usage: collector --state-dir DIR -- COMMAND [ARGS...]")
		os.Exit(2)
	}
	state, args := os.Args[2], os.Args[4:]
	lockFD, e1 := strconv.Atoi(os.Getenv("MARGIN_LEADER_FD"))
	parentFD, e2 := strconv.Atoi(os.Getenv("MARGIN_PARENT_FD"))
	if e1 != nil || e2 != nil {
		fmt.Fprintln(os.Stderr, "missing inherited descriptors")
		os.Exit(2)
	}
	lock := os.NewFile(uintptr(lockFD), "leader")
	parent := os.NewFile(uintptr(parentFD), "parent")
	stop := make(chan struct{}, 1)
	go func() { _, _ = io.Copy(io.Discard, parent); stop <- struct{}{} }()
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	fd, err := syscall.InotifyInit1(syscall.IN_NONBLOCK | syscall.IN_CLOEXEC)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer syscall.Close(fd)
	task := os.Getenv("TASKDATA")
	if task == "" {
		task = filepath.Join(os.Getenv("HOME"), ".task")
	}
	notes := filepath.Join(os.Getenv("HOME"), ".claude", "tmp")
	probe := os.Getenv("HANDOFF_PROBE_STATE")
	if probe == "" {
		base := os.Getenv("XDG_STATE_HOME")
		if base == "" {
			base = filepath.Join(os.Getenv("HOME"), ".local", "state")
		}
		probe = filepath.Join(base, "handoff-probe", "state.json")
	}
	taskrc := os.Getenv("TASKRC")
	if taskrc == "" {
		taskrc = filepath.Join(os.Getenv("HOME"), ".taskrc")
	}
	type watch struct{ kind, name string }
	watches := map[int][]watch{}
	var watchKeys []string
	add := func(path, kind, name string) {
		wd, err := syscall.InotifyAddWatch(fd, path, syscall.IN_MODIFY|syscall.IN_CLOSE_WRITE|syscall.IN_MOVED_TO|syscall.IN_CREATE|syscall.IN_DELETE|syscall.IN_ATTRIB|syscall.IN_MOVE_SELF|syscall.IN_DELETE_SELF)
		if err == nil {
			watches[wd] = append(watches[wd], watch{kind, name})
			watchKeys = append(watchKeys, fmt.Sprintf("%s:%s:%s:%d", path, kind, name, wd))
		}
	}
	// Refresh the small watch set to pick up directories that appear or are replaced.
	refreshWatches := func() string {
		watches = map[int][]watch{}
		watchKeys = nil
		add(state, "state", "")
		add(notes, "notes", "")
		entries, _ := os.ReadDir(notes)
		for _, entry := range entries {
			if entry.IsDir() && (entry.Name() == "cockpit-updates" || strings.HasPrefix(entry.Name(), "cockpit-pr-")) {
				add(filepath.Join(notes, entry.Name()), "nested", "")
			}
		}
		add(task, "task", "")
		add(filepath.Dir(taskrc), "file", filepath.Base(taskrc))
		add(filepath.Dir(probe), "file", filepath.Base(probe))
		sort.Strings(watchKeys)
		return strings.Join(watchKeys, "\n")
	}
	watchSignature := refreshWatches()
	relevant := func(w watch, name string) bool {
		switch w.kind {
		case "state":
			return name == "dirty"
		case "notes":
			return name == "cockpit-notes.md" || name == "cockpit-updates" || strings.HasPrefix(name, "cockpit-pr-")
		case "nested":
			return name != "" && !strings.HasPrefix(name, ".") && name != "designs" && !strings.HasSuffix(name, "-shm") && !strings.HasSuffix(name, ".try") && !strings.HasSuffix(name, ".lock") && !strings.Contains(name, ".tmp.")
		case "file":
			return name == w.name
		case "task":
			return name == "pending.data" || name == "completed.data" || name == "undo.data" || name == "backlog.data" || name == "taskchampion.sqlite3" || name == "taskchampion.sqlite3-wal" || strings.HasSuffix(name, ".data") || strings.HasSuffix(name, ".db") || strings.HasSuffix(name, ".db-wal")
		}
		return false
	}
	ticker := time.NewTicker(50 * time.Millisecond)
	defer ticker.Stop()
	due := time.Now()
	nextAge := time.Now().Add(60 * time.Second)
	var nextFingerprint time.Time
	var cmd *exec.Cmd
	var result chan error
	var output strings.Builder
	var lastFingerprint, pendingFingerprint, notesCache string
	var pendingValid bool
	orderFile := filepath.Join(state, "pane-order")
	cycleDir := os.Getenv("CYCLE_AGENT_CACHE_DIR")
	if cycleDir == "" {
		runtime := os.Getenv("XDG_RUNTIME_DIR")
		if runtime == "" {
			runtime = "/tmp"
		}
		cycleDir = filepath.Join(runtime, "cycle-agent-order")
	}
	nextWatches := time.Now().Add(200 * time.Millisecond)
	start := func() {
		output.Reset()
		_ = os.Remove(orderFile)
		cmd = exec.Command(args[0], args[1:]...)
		cmd.Stdout = &output
		cmd.Stderr = io.Discard
		cmd.Env = append(os.Environ(), "TMUX_PANE=", "COCKPIT_ORDER_FILE="+orderFile)
		cmd.ExtraFiles = []*os.File{lock}
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		if err := cmd.Start(); err != nil {
			result = make(chan error, 1)
			result <- err
			return
		}
		result = make(chan error, 1)
		go func(c *exec.Cmd, ch chan error) { ch <- c.Wait() }(cmd, result)
	}
	defer func() {
		if cmd != nil && cmd.Process != nil {
			_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM)
			<-result
		}
	}()
	buf := make([]byte, 65536)
	for {
		select {
		case <-stop:
			return
		case <-signals:
			return
		case err := <-result:
			if err == nil {
				if pendingValid {
					lastFingerprint = pendingFingerprint
				}
				// Keep identity and text in one publication. The cycle shortcut may
				// replace its own order independently while a viewer is painting.
				order, _ := os.ReadFile(orderFile)
				frame, _ := json.Marshal(struct {
					Text  string   `json:"text"`
					Panes []string `json:"panes"`
				}{output.String(), strings.Fields(string(order))})
				tmp := filepath.Join(state, fmt.Sprintf(".frame.%d.tmp", os.Getpid()))
				if os.WriteFile(tmp, frame, 0600) == nil {
					_ = os.Rename(tmp, filepath.Join(state, "frame"))
				}
				if order != nil && os.MkdirAll(cycleDir, 0700) == nil {
					tmp := filepath.Join(cycleDir, fmt.Sprintf(".order.%d.tmp", os.Getpid()))
					if os.WriteFile(tmp, order, 0600) == nil {
						_ = os.Rename(tmp, filepath.Join(cycleDir, "order"))
					}
				}
			} else if _, statErr := os.Stat(filepath.Join(state, "frame")); os.IsNotExist(statErr) {
				_ = os.WriteFile(filepath.Join(state, "frame"), []byte("Roster read failed\n"), 0600)
			}
			cmd, result = nil, nil
		case now := <-ticker.C:
			for {
				n, err := syscall.Read(fd, buf)
				if err != nil || n <= 0 {
					break
				}
				for pos := 0; pos+syscall.SizeofInotifyEvent <= n; {
					ev := (*syscall.InotifyEvent)(unsafe.Pointer(&buf[pos]))
					pos += syscall.SizeofInotifyEvent
					if pos+int(ev.Len) > n {
						break
					}
					if ev.Mask&syscall.IN_Q_OVERFLOW != 0 {
						notesCache = ""
						due = now.Add(150 * time.Millisecond)
					}
					name := strings.TrimRight(string(buf[pos:pos+int(ev.Len)]), "\x00")
					pos += int(ev.Len)
					for _, w := range watches[int(ev.Wd)] {
						// SQLite opens and closes its WAL even for read-only queries.
						// Those events do not establish that task data changed.
						if w.kind == "task" && (name == "taskchampion.sqlite3" || name == "taskchampion.sqlite3-wal") {
							mask := uint32(syscall.IN_MODIFY | syscall.IN_MOVED_TO | syscall.IN_ATTRIB)
							if name == "taskchampion.sqlite3" {
								mask |= syscall.IN_CREATE | syscall.IN_DELETE
							}
							if ev.Mask&mask == 0 {
								continue
							}
						}
						if relevant(w, name) {
							if w.kind == "notes" || w.kind == "nested" {
								notesCache = ""
							}
							if due.IsZero() {
								due = now.Add(150 * time.Millisecond)
							}
						}
					}
				}
			}
			if !now.Before(nextWatches) {
				signature := refreshWatches()
				if signature != watchSignature {
					notesCache = ""
					if due.IsZero() {
						due = now.Add(150 * time.Millisecond)
					}
				}
				watchSignature = signature
				nextWatches = now.Add(200 * time.Millisecond)
			}
			if cmd == nil && !now.Before(nextFingerprint) && ((!due.IsZero() && !now.Before(due)) || !now.Before(nextAge)) {
				ageRefresh := !now.Before(nextAge)
				if ageRefresh {
					notesCache = "" // Recover from a missed watch or event.
				}
				due = time.Time{}
				pendingValid = false
				if os.Getenv("TMUX_READING_MARGIN_SEMANTIC_FILTER") != "0" {
					nextFingerprint = now.Add(time.Second)
					fingerprint, err := fingerprint(task, notes, taskrc, probe, &notesCache)
					if err != nil {
						_ = os.WriteFile(filepath.Join(state, "fingerprint-error"), []byte(fmt.Sprintf("%s: %v\n", time.Now().Format(time.RFC3339), err)), 0600)
						due = now.Add(2 * time.Second)
						nextFingerprint = due
						nextAge = now.Add(60 * time.Second)
						start()
						continue
					}
					_ = os.Remove(filepath.Join(state, "fingerprint-error"))
					pendingFingerprint, pendingValid = fingerprint, true
					if !ageRefresh && lastFingerprint != "" && fingerprint == lastFingerprint {
						continue
					}
				}
				nextAge = now.Add(60 * time.Second)
				start()
			}
		}
	}
}
