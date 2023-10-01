#!/bin/bash

# fail as soon as any command errors
set -e

token=$1
update_command=$2
pr_branch=$3
update_path=$4
on_changes_command=$5
repo=$GITHUB_REPOSITORY #owner and repository: ie: user/repo
username=$GITHUB_ACTOR

job_date=$(date +"%Y-%m-%d")
branch_name="dependencies-update-$job_date"
email="noreply@github.com"

if [ -z "$token" ]; then
    echo "token is not defined"
    exit 1
fi

if [ -z "$update_command" ]; then
    echo "update-command cannot be empty"
    exit 1
fi

if [ -z "$pr_branch" ]; then
    echo "pr-branch not set, falling back to `main`"
    pr_branch="main"
fi

# remove optional params markers
update_path_value=${update_path%?}
if [ -n "$update_path_value" ]; then
    # if path is set, use that. otherwise default to current working directory
    echo "Change directory to $update_path_value"
    cd "$update_path_value"
fi

# assumes the repo is already cloned as a prerequisite for running the script

# fetch first to be able to detect if branch already exists 
git fetch

branch_exists=$(git branch --list $branch_name)

# branch already exists, previous opened PR was not merged
if [ -z "$branch_exists" ]; then
    # create new branch
    git checkout -b $branch_name
else
    echo "Branch name $branch_name already exists"

    # check out existing branch
    echo "Check out branch instead" 
    git checkout $branch_name
    git pull

    # reset with latest from $pr_branch
    # this avoids merge conflicts when existing changes are not merged
    git reset --hard origin/$pr_branch
fi

echo "Running update command $update_command"
eval $update_command

if [ -n "git diff" ]
then
    echo "Updates detected"

    # configure git authorship
    git config --global user.email $email
    git config --global user.name $username

    # format: https://[username]:[token]@github.com/[organization]/[repo].git
    git remote add authenticated "https://$username:$token@github.com/$repo.git"

    # execute command to run when changes are deteced, if provided
    on_changes_command_value=${on_changes_command%?}
    echo $on_changes_command_value
    if [ -n "$on_changes_command_value" ]; then
        echo "Run post-update command"
        eval $on_changes_command_value
    fi

    # explicitly add all files including untracked
    git add -A

    # commit the changes to updated files
    git commit -a -m ":arrow_up: Auto-updated dependencies on $job_date" --signoff
    
    # push the changes
    git push authenticated -f

    echo "https://api.github.com/repos/$repo/pulls"

    # create the PR
    # if PR already exists, then update
    title=":arrow_up: Dependencies updated on $job_date"
    pr_message="### $title \nThis pull request is generated by GitHub action based on the provided update commands."
    response=$(curl --write-out "%{message}\n" -X POST -H "Content-Type: application/json" -H "Authorization: token $token" \
         --data '{"title":"'"$title"'","head": "'"$branch_name"'","base":"'"$pr_branch"'", "body":"'"$pr_message"'"}' \
         "https://api.github.com/repos/$repo/pulls")
    
    echo $response   

    if [[ "$response" == *"already exist"* ]]; then
        echo "Pull request already opened. Updates were pushed to the existing PR instead"
        exit 0
    fi
else
    echo "No dependencies updates were detected"
    exit 0
fi
