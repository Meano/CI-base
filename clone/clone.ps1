$ErrorActionPreference = 'Stop';

function Initialize-Gitenvironment() {
    if ($env:DRONE_WORKSPACE) {
        Write-Output "+ Set location to workspace"
        Set-Location $env:DRONE_WORKSPACE
    }

    Write-Output "+ Set git environment variables"
    if ($env:PLUGIN_SKIP_VERIFY) {
        $env:GIT_SSL_NO_VERIFY = "true"
    }
    
    if (!$env:DRONE_COMMIT_AUTHOR_NAME) {
        $env:GIT_AUTHOR_NAME = $env:DRONE_COMMIT_AUTHOR_NAME
    }
    else {
        $env:GIT_AUTHOR_NAME = "drone"
    }

    if (!$env:DRONE_COMMIT_AUTHOR_EMAIL) {
        $env:GIT_AUTHOR_EMAIL = $env:DRONE_COMMIT_AUTHOR_EMAIL
    }
    else {
        $env:GIT_AUTHOR_EMAIL = 'drone@localhost'
    }

    $env:GIT_COMMITTER_NAME = $env:GIT_AUTHOR_NAME
    $env:GIT_COMMITTER_EMAIL = $env:GIT_AUTHOR_EMAIL

    if ($env:PLUGIN_DEPTH -and $env:DRONE_BUILD_EVENT -ne "tag") {
        $env:PLUGIN_FETCH_OPTIONS = "--depth=$env:PLUGIN_DEPTH" 
    }
}

function Initialize-GitRepo() {
    if ($env:PLUGIN_PATH) {
        Write-Output "+ Init repo to: $env:PLUGIN_PATH"
        git init "$env:PLUGIN_PATH"
        Set-Location "$env:PLUGIN_PATH"
    }
    else {
        Write-Output "+ Init repo"
        git init
    }
    git remote add origin $env:DRONE_REMOTE_URL

    if (!$env:DRONE_TAG) {
        $gitTagLines = "$(git ls-remote -q --refs --tags)".Split("\n")
        if ($gitTagLines -and $gitTagLines[-1] -match '([\w\s]*refs/tags/)(v\d*\.\d*\.\d*(-\w+)?)') {
            $env:CI_SHARE_GIT_TAG = $MATCHES[2]
        }
        else {
            $env:CI_SHARE_GIT_TAG = "v0.0.0-dev"
        }
    }
    else {
        $env:CI_SHARE_GIT_TAG = $env:DRONE_TAG
    }
    if ($env:CI_SHARE_GIT_TAG -match 'v(\d*\.\d*\.\d*)(-)?(\w+)?') {
        $env:CI_SHARE_GIT_TAG_SHORT = $MATCHES[1]
        $env:CI_SHARE_GIT_TAG_PRERELEASE = $MATCHES[3]
    }
}

function Get-GitCommit() {
    Write-Output "+ Get git commit"
    git fetch $env:PLUGIN_FETCH_OPTIONS origin "+refs/heads/${env:DRONE_COMMIT_BRANCH}:"
    git checkout $env:DRONE_COMMIT_SHA -b $env:DRONE_COMMIT_BRANCH
}

function Get-GitPullRequest() {
    Write-Output "+ Get git pull request"
    git fetch $env:PLUGIN_FETCH_OPTIONS  origin "+refs/heads/${env:DRONE_COMMIT_BRANCH}:"
    git checkout $env:DRONE_COMMIT_BRANCH

    git fetch origin "${env:DRONE_COMMIT_REF}:"
    git merge $env:DRONE_COMMIT_SHA
}

function Get-GitTag() {
    Write-Output "+ Get git tag"
    git fetch $FLAGS origin -t "+refs/tags/${env:DRONE_TAG}:"
    git checkout -qf FETCH_HEAD
    # fetch the repo branch
    git fetch origin $env:DRONE_REPO_BRANCH
    if (git branch -r --contains $env:DRONE_TAG --format "%(refname:short)" "origin/$env:DRONE_REPO_BRANCH") {
        $env:CI_SHARE_GIT_TAG_RELEASE = "true"
    }
    else {
        $env:CI_SHARE_GIT_TAG_RELEASE = ""
    }
}

Initialize-Gitenvironment
Initialize-GitRepo

switch ($env:DRONE_BUILD_EVENT) {
    "pull_request" {
        Get-GitPullRequest
        break
    }
    "tag" {
        Get-GitTag
        break
    }
    default {
        Get-GitCommit
        break
    }
}

Write-Output "+ Git clone done!"
