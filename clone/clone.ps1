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

    git config versionsort.suffix -

    $gitTagRef = ""
    if (!$env:DRONE_TAG) {
        $gitTagRefLines = $(git ls-remote -q --refs --sort='v:refname' --tags origin 'v*')
        if ($gitTagRefLines) {
            $gitTagRef = $gitTagRefLines.Split("\n")[-1]
        }
    }
    else {
        $gitTagRef = $env:DRONE_TAG
    }

    if ($gitTagRef -match '^(\w*?)?(?:\s*?refs/tags/)?v(((\d*)\.(\d*)\.(\d*))(?:-([\w\.]+))?)$') {
        $env:CI_SHARE_GIT_SEMVER = $MATCHES[2]
        $env:CI_SHARE_GIT_SEMVER_SHORT = $MATCHES[3]
        $env:CI_SHARE_GIT_SEMVER_MAJOR = $MATCHES[4]
        $env:CI_SHARE_GIT_SEMVER_MINOR = $MATCHES[5]
        $env:CI_SHARE_GIT_SEMVER_PATCH = $MATCHES[6]
        $env:CI_SHARE_GIT_SEMVER_PRERELEASE = $MATCHES[7]
        $env:CI_SHARE_GIT_TAG_ID = $MATCHES[2]
    }
    else {
        $env:CI_SHARE_GIT_SEMVER = "0.0.0-dev"
        $env:CI_SHARE_GIT_SEMVER_SHORT = "0.0.0"
        $env:CI_SHARE_GIT_SEMVER_MAJOR = "0"
        $env:CI_SHARE_GIT_SEMVER_MINOR = "0"
        $env:CI_SHARE_GIT_SEMVER_PATCH = "0"
        $env:CI_SHARE_GIT_SEMVER_PRERELEASE = "dev"
    }

    if (!$env:DRONE_TAG -and !$env:CI_SHARE_GIT_SEMVER_PRERELEASE) {
        if ($env:DRONE_COMMIT_SHA -ne $env:CI_SHARE_GIT_TAG_ID) {
            $env:CI_SHARE_GIT_SEMVER_PATCH = [Int]$env:CI_SHARE_GIT_SEMVER_PATCH + 1
        }
        $env:CI_SHARE_GIT_SEMVER_PRERELEASE = "dev"
        $env:CI_SHARE_GIT_SEMVER_SHORT = "$env:CI_SHARE_GIT_SEMVER_MAJOR.$env:CI_SHARE_GIT_SEMVER_MINOR.$env:CI_SHARE_GIT_SEMVER_PATCH"
        $env:CI_SHARE_GIT_SEMVER = "$env:CI_SHARE_GIT_SEMVER_SHORT-$env:CI_SHARE_GIT_SEMVER_PRERELEASE"
    }

    Write-Output "Git SemVer: $env:CI_SHARE_GIT_SEMVER"
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

    # check if the release tags on the default branch of the repo
    if ($env:CI_SHARE_GIT_SEMVER_PRERELEASE) {
        $env:DRONE_COMMIT_BRANCH = "tag"
        return
    }

    # fetch the repo branch
    git fetch origin $env:DRONE_REPO_BRANCH
    if (git branch -r --contains $env:DRONE_TAG --format "%(refname:short)" "origin/$env:DRONE_REPO_BRANCH") {
        $env:CI_SHARE_GIT_SEMVER_DRAFT = ""
        $env:DRONE_COMMIT_BRANCH = $env:DRONE_REPO_BRANCH
    }
    else {
        $env:CI_SHARE_GIT_SEMVER_DRAFT = "true"
        $env:DRONE_COMMIT_BRANCH = "draft"
        Write-Output "+ The release tag ($env:DRONE_TAG) is not belong to the default branch ($env:DRONE_REPO_BRANCH) of the repo."
    }
}

function Get-GitBuildInfo() {
    $env:CI_SHARE_GIT_COMMIT_SHA_SHORT = (git rev-parse --short HEAD)
    $env:CI_SHARE_GIT_BUILD_INFO = "+$env:DRONE_COMMIT_BRANCH.$(Get-Date -Format 'yyyyMMdd').$('{0:d6}' -f [convert]::ToInt32($env:DRONE_BUILD_NUMBER)).$env:CI_SHARE_GIT_COMMIT_SHA_SHORT"
    Write-Output "+ Git build info: $env:CI_SHARE_GIT_BUILD_INFO"
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

Get-GitBuildInfo

Write-Output "+ Git clone done!"
