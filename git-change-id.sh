#!/usr/bin/env bash
# ============================================================================
# git-change-id.sh - Changes your email in repo
# change your email in git config and the run the script
# 
# Flags:
# --github=GithubName clones all your public repos needs user name
# --name=NewGitName
# --old=OldEmail you can provide multiple old mails
# --new=NewEmail
# --search searches for all you git repos in folder
# --push   auto force push repo 
# --check reads all git emails
# --config=PATH a file containing all flags (no -- required)
#
# Requirements:
#   - git
#   - curl
#   - python3
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CLEAR='\033[0m'

ARGS="$@"
LOCAL_PATH="$(pwd | sed 's#/[^/]*$##')"

PUSH=false
METHOD=""
GITHUB=""
CHECK=false
NAME=""
OLD=""
NEW=""
CLEANUP=false

parse_args() {
  for arg in $1; do
    if [[ "$arg" == "#"* ]]; then
      continue
    fi

    case "$arg" in
      --push|push) 
        PUSH=true
      ;;
      --search|search)
        METHOD=search
      ;;
      --github=*)
        METHOD=github
        GITHUB="${arg#--github=}"
      ;;
      github=*)
        METHOD=github
        GITHUB="${arg#github=}"
      ;;
      --name=*)
        NAME="${arg#--name=}"
      ;;
      name=*)
        NAME="${arg#name=}"
      ;;
      --old=*)
        OLD="$OLD ${arg#--old=}"
      ;;
      old=*)
        OLD="$OLD ${arg#old=}"
      ;;
      --new=*)
        NEW="${arg#--new=}"
      ;;
      new=*)
        NEW="${arg#new=}"
      ;;
      --check|check)
        CHECK=true
      ;;
      --cleanup|cleanup) 
        CLEANUP=true
      ;;
      --config=*)
        parse_args "$(cat ${arg#--config=})"
      ;;
      config=*)
        parse_args "$(cat ${arg#config=})"
      ;;
    esac
  done
}

handle_args() {
  parse_args "$ARGS"

  if [[ -z $NAME && -n $GITHUB ]]; then 
    NAME=$GITHUB
  fi

  if [[ $CHECK == "false" && (  -z "$NAME" || -z "$OLD" || -z "$NEW" ) ]]; then
    echo -e "${RED}You need to set name, old and new if you want to change sth!${CLEAR}"
    exit 1
  fi
}

push_changes() {
  if $PUSH; then 
    git push --force  
    echo -e "${GREEN}Pushed!${CLEAR}"
  else  
    read -p "Push changes? (y/n) " answer
    case $answer in
      [yY]*) 
        git push --force
        echo -e "${GREEN}Pushed!${CLEAR}"
      ;;
    esac
  fi
}

reset_repo() {
  config=$1
  branch=$2

  rm ./.mailmap
  echo "$config" > ./.git/config
  git fetch origin -q
}

change_id() {
  config=$(cat ./.git/config)
  branch=$(git branch --show-current)

  git stash -q

  for mail in $OLD; do
    echo "$NAME <$NEW> <$mail>" >> "./.mailmap"
  done
  python3 $LOCAL_PATH/git-filter-repo.py --use-mailmap --force  #> /dev/null 2>&1
  
  if [[ $? != "0" ]]; then
    echo -e "${RED}Exception while changing history.${CLEAR}"
  else 
    echo -e "${GREEN}Successfully changed id!${CLEAR}"
  fi

  reset_repo "$config" "$branch"
  push_changes;
}

check_branches() {
  branches="$(git branch -r | grep -v 'origin/HEAD ->' )"
  
  for branch in $branches; do 
    git stash -q
    git switch ${branch#origin/} -q 

    echo "($branch):"
    
    if $CHECK; then 
      git log --pretty=format:%ae | sort -u
    else
      change_id
    fi

    echo ""
  done  
}

run_action() {   
  dir=$1
  cd $dir

  if [ ! -d "$dir/.git" ]; then
     echo "$dir does not contain a git repo."
  else 
    check_branches
  fi
}

clean_up() {
  cd $LOCAL_PATH
  if $CLEANUP; then 
    rm -rf cloned-repos 
  else  
    read -p "Clean up? (y/n)" answer
    case $answer in
      [yY]*) rm -rf cloned-repos
      ;;
    esac
  fi
}

github() {
  mkdir -p cloned-repos
  cd cloned-repos

  repos=$(curl -s https://api.github.com/users/$GITHUB/repos | grep -oP '"clone_url":\s*"\K[^"]+')

  for repo in $repos; do
    git clone $repo -q

    if [[ $? = "0" ]]; then
      echo -e "${GREEN}Cloned $(echo "$repo" | grep -oP '\/(?!.*\/)\K.*(?=.git)')!${CLEAR}"
    fi
  done

  echo ""

  search $PWD

  clean_up
}

search() {
  dirs=$(find "$1" -mindepth 1 -maxdepth 1 -type d)
  for dir in $dirs; do
    if [ -d "$dir/.git" ]; then
      echo "$(echo "$dir" | grep -oP '\/(?!.*\/)\K.*'):"
      run_action $dir
      echo ""
    fi
  done
}

handle_args

#Install script
if ! $CHECK; then
  curl -s https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo > "$LOCAL_PATH/git-filter-repo.py"
fi

case $METHOD in
  github)
    github
  ;;
  search)
    search "$LOCAL_PATH"
  ;;
  *)
    run_action $PWD
  ;;
esac

if [[ $CHECK == "false" && -n $METHOD ]]; then
  rm $LOCAL_PATH/git-filter-repo.py
fi
