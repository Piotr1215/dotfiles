import webbrowser
base="https://duckduckgo.com/?q="
phrase=clipboard.get_selection()

#Remove trailing or leading white space and find if there are multiple
#words.
phrase=phrase.strip()
singleWord=False
if phrase.find(' ')<0:
    singleWord=True

#Generate search URL.
if singleWord:
    search_url=base+phrase
if (not singleWord):
    phrase='+'.join(phrase.split())
    search_url=base+phrase

webbrowser.open_new_tab(search_url)