#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -euo pipefail

# See bin/finalize to check predefined vars
ROOT="/home/vcap"
export APP_ROOT="${ROOT}/app"
export AUTH_ROOT="${ROOT}/auth"

export BINDING_NAME="${BINDING_NAME:-}"
export LOCATION="${LOCATION:-europe-west4}"

export AUTH_USER="${AUTH_USER:-admin}"
export AUTH_PASSWORD="${AUTH_PASSWORD:-}"

###

get_binding_service() {
    local binding_name="${1}"
    jq --arg b "${binding_name}" '[.[][] | select(.binding_name == $b)]' <<<"${VCAP_SERVICES}"
}

services_has_tag() {
    local services="${1}"
    local tag="${2}"
    jq --arg t "${tag}" -e '.[].tags | contains([$t])' <<<"${services}" >/dev/null
}

get_s3_service() {
    local name=${1:-"aws-s3"}
    jq --arg n "${name}" '.[$n]' <<<"${VCAP_SERVICES}"
}

get_gcs_service() {
    local name=${1:-"google-storage"}
    jq --arg n "${name}" '.[$n]' <<<"${VCAP_SERVICES}"
}

set_s3_config() {
    local services="${1}"

    export PROVIDER=s3
    export AWS_SECRET_ACCESS_KEY=$(jq -r -e '.[] | .credentials.SECRET_ACCESS_KEY' <<<"${services}")
    export AWS_ACCESS_KEY_ID=$(jq -r -e '.[] | .credentials.ACCESS_KEY_ID' <<<"${services}")
    export REGION=$(jq -r -e '.[] | (.credentials.S3_API_URL | split(".")[0] | split("s3-")[1])' <<<"${services}")
    export BUCKET="${PROVIDER}://$(jq -r -e '.[] | .credentials.BUCKET_NAME' <<<${services})/"
    [ -z "${REGION}" ] && REGION=${LOCATION}
}

set_gcs_config() {
    local services="${1}"

    export PROVIDER=gcs
    for s in $(jq -r '.[] | .name' <<<"${services}")
    do
        jq -r --arg n "${s}" '.[] | select(.name == $n) | .credentials.PrivateKeyData' <<<"${services}" | base64 -d > "${AUTH_ROOT}/${s}-auth.json"
    done
    export GOOGLE_APPLICATION_CREDENTIALS="${AUTH_ROOT}/$(jq -r -e '.[] | .name' <<<${services})-auth.json"
    export BUCKET="${PROVIDER}://$(jq -r -e '.[] | .credentials.bucket_name' <<<${services})/"
    export REGION=${LOCATION}
}


set_config_from_vcap_services() {
    local binding_name="${1}"
    local service=""

    if [ -n "${binding_name}" ] && [ "${binding_name}" != "null" ]
    then
        service=$(get_binding_service "${binding_name}")
        if [ -n "${service}" ] && [ "${service}" != "null" ]
        then
            if services_has_tag "${service}" "gcp"
            then
                set_gcs_config"${service}"
            else
                set_s3_config "${service}"
            fi
        else
            return 1
        fi
    else
        service=$(get_s3_service)
        if [ -n "${service}" ] && [ "${service}" != "null" ]
        then
            set_s3_config "${service}"
        fi
        service=$(get_gcs_service)
        if [ -n "${service}" ] && [ "${service}" != "null" ]
        then
            set_gcs_config "${service}"
        fi
    fi
    return 0
}

get_bucket_from_service() {
    local s="${1}"
    local services="${2}"

    local bucket=""
    local rvalue=0

    # first, try GCS style
    bucket=$(jq -r -e --arg s "${s}" '.[][] | select(.name == $s) | .credentials.bucket_name' <<<"${services}")
    rvalue=$?
    # if empty, try S3
    if [ -z "${bucket}" ] || [ ${rvalue} -ne 0 ]
    then
        bucket=$(jq -r -e --arg s "${s}" '.[][] | select(.name == $s) | .credentials.BUCKET_NAME' <<<"${services}")
        rvalue=$?
    fi
    echo $bucket
    return $rvalue
}


# exec process
launch() {
    local cmd="${1}"
    shift

    local pid
    local rvalue
    (
        echo ">> Launching pid=$$: $cmd $@"
        {
            exec $cmd $@
        } 2>&1
    ) &
    pid=$!
    sleep 10
    if ! ps -p ${pid} >/dev/null 2>&1
    then
        echo ">> Error launching: '$cmd $@'"  >&2
        return 1
    fi
    wait ${pid} 2>/dev/null
    rvalue=$?
    echo ">> Finish pid=${pid}: ${rvalue}"
    return ${rvalue}
}


# Run
if ! set_config_from_vcap_services  "${BINDING_NAME}"
then
    echo ">> Error, service '${BINDING_NAME}' not found!" >&2
    exit 1
fi
cat $GOOGLE_APPLICATION_CREDENTIALS
launch s3server -p ${PORT} -provider ${PROVIDER} -bucket ${BUCKET}
