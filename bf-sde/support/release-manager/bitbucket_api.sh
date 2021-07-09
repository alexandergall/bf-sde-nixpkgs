get_tags () {
    local result
    result=$(api_call '/tags?limit=1000')
    jq -rc '.values[].displayId' <<<$result
}

get_branch_commits () {
    local gitTag commit_head commit_tag
    gitTag=$1
    commit_head=$(api_call '/branches?limit=1000&filterText='$(branch_from_tag $gitTag) | jq -r '.values[0].latestCommit')
    commit_tag=$(api_call '/tags?limit=1000&filterText='$(branch_from_tag $gitTag) | jq -r '.values[0].latestCommit')
    echo $commit_head $commit_tag
}

fetch_and_unpack_tarball () {
    local gitTag
    gitTag=$1
    curl -L --output ${gitTag}.tar.gz $API_URL'/archive?at='$gitTag'&format=tar.gz' 2>/dev/null
    tar xf release-*
}

commit_hash_from_tag () {
    local gitTag
    gitTag=$1
    api_call '/branches?limit=1000&filterText='$(branch_from_tag $gitTag) | jq -r '.values[0].latestCommit'
}
