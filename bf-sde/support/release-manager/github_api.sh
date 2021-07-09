get_tags () {
    local result
    result=$(api_call /tags)
    jq -r '.[].name' <<<$result
}

get_branch_commits () {
    local gitTag tag_sha commit_head commit_tag
    gitTag=$1
    commit_head=$(api_call /git/ref/heads/$(branch_from_tag $gitTag) | jq -r '.object.sha')
    tag_sha=$(api_call /git/ref/tags/$gitTag | jq -r '.object.sha')
    commit_tag=$(api_call /git/tags/$tag_sha | jq -r '.object.sha')
    echo $commit_head $commit_tag
}

fetch_and_unpack_tarball () {
    local gitTag tarball
    gitTag=$1
    tarball=$REPO_GIT/archive/$gitTag.tar.gz
    curl -L -O $tarball 2>/dev/null
    tar xf release-* --strip-component 1
}

commit_hash_from_tag () {
    local gitTag
    gitTag=$1
    api_call /git/ref/heads/$(branch_from_tag $gitTag) | jq -r '.object.sha'
}
