default:
  just --list

stow:
  stow -R -v -t ~ .

adopt:
  stow -R -v -t ~ . --adopt
