#!/bin/bash

#
# MIT license
# Copyright (c) 2024 llama-box authors
# SPDX-License-Identifier: MIT
#

LOG_FILE=${LOG_FILE:-/dev/null}

API_URL="${API_URL:-http://127.0.0.1:8080}"

trim() {
    shopt -s extglob
    set -- "${1##+([[:space:]])}"
    printf "%s" "${1%%+([[:space:]])}"
}

trim_trailing() {
    shopt -s extglob
    printf "%s" "${1%%+([[:space:]])}"
}

N="${N:-"1"}"
RESPONSE_FORMAT="b64_json"
SIZE="${SIZE:-"512x512"}"
QUALITY="${QUALITY:-"standard"}"
IMAGE="${IMAGE:-""}"
MASK="${MASK:-""}"
SAMPLER="${SAMPLER:-"null"}"
SEED="${SEED:-"null"}"
CFG_SCALE="${CFG_SCALE:-"9"}"
SAMPLE_STEPS="${SAMPLE_STEPS:-"20"}"
NEGATIVE_PROMPT="${NEGATIVE_PROMPT:-""}"

parse() {
    echo "A: ${LINE}" >>"${LOG_FILE}"
    if [[ ! "${LINE}" = data:* ]]; then
        if [[ "${LINE}" =~ error:.* ]]; then
            LINE="${LINE:7}"
            echo "Error: ${LINE}"
        fi
        return 0
    fi
    if [[ "${LINE}" =~ data:\ \[DONE\].* ]]; then
        return 0
    fi
    LINE="${LINE:5}"
    CONTENT="$(echo "${LINE}" | jq -cr '.data')"
    if [[ "${CONTENT}" == "null" ]]; then
        echo "Error: ${LINE}"
        return 1
    fi
    RESULT_JSON="/tmp/image_edit_$(date +%s).json"
    printf "%s" "${LINE}" >"${RESULT_JSON}"
    printf "%i: %3.2f%%...\r" "$(jq -cr ".data[0] | .index" "${RESULT_JSON}")" "$(jq -cr ".data[0] | .progress" "${RESULT_JSON}")"
    if [[ "$(jq -cr ".data[0] | .b64_json" "${RESULT_JSON}")" == "null" ]]; then
        return 0
    fi
    printf "\n"
    set +e
    RESULT_PNG="/tmp/image_edit_$(date +%s).png"
    if command -v gbase64 >/dev/null; then
        jq -cr ".data[0] | .b64_json" "${RESULT_JSON}" | gbase64 -d >"${RESULT_PNG}"
    else
        jq -cr ".data[0] | .b64_json" "${RESULT_JSON}" | base64 -d >"${RESULT_PNG}"
    fi
    echo "Generated image: ${RESULT_PNG}"
    if [[ "$(uname -s)" =~ Darwin ]]; then
        if command -v feh >/dev/null; then
            feh "${RESULT_PNG}"
        elif command -v open >/dev/null; then
            open "${RESULT_PNG}"
        fi
    fi
    set -e
    USAGE="$(jq -cr '.usage' "${RESULT_JSON}")"
    if [[ "${USAGE}" != "null" ]]; then
        printf "\n------------------------"
        printf "\n- TTP  : %10.2fms  -" "$(echo "${USAGE}" | jq -cr '.time_to_process_ms')"
        printf "\n- TPG  : %10.2fms  -" "$(echo "${USAGE}" | jq -cr '.time_per_generation_ms')"
        printf "\n- GPS  : %10.2f    -" "$(echo "${USAGE}" | jq -cr '.generation_per_second')"
        ELAPSED=$(($(date +%s) - START_TIME))
        printf "\n- TC   : %10.2fs   -" "${ELAPSED}"
        printf "\n------------------------"
    fi
    return 0
}

image_edit() {
    PROMPT="$(trim_trailing "$1")"
    if [[ "${IMAGE:0:1}" == "@" ]]; then
        IMAGE="${IMAGE:1}"
    fi
    if [[ ! -f "${IMAGE}" ]]; then
        echo "Image not found: ${IMAGE}" && exit 1
    fi
    if [[ -n "${MASK}" ]]; then
        if [[ "${MASK:0:1}" == "@" ]]; then
            MASK="${MASK:1}"
        fi
        if [[ ! -f "${MASK}" ]]; then
            echo "Mask not found: ${MASK}" && exit 1
        fi
    fi
    DATA="{\"prompt\":\"${PROMPT}\"}"
    if [[ "${SAMPLER}" != "null" ]]; then
        DATA="$(echo -n "${DATA}" | jq \
            --argjson n "${N}" \
            --argjson response_format "\"${RESPONSE_FORMAT}\"" \
            --argjson size "\"${SIZE}\"" \
            --argjson sampler "\"${SAMPLER}\"" \
            --argjson seed "${SEED}" \
            --argjson cfg_scale "${CFG_SCALE}" \
            --argjson sample_steps "${SAMPLE_STEPS}" \
            --argjson negative_prompt "\"${NEGATIVE_PROMPT}\"" \
            --argjson image "\"${IMAGE}\"" \
            --argjson mask "\"${MASK}\"" \
            '{
                  n: $n,
                  response_format: $response_format,
                  size: $size,
                  sampler: $sampler,
                  seed: $seed,
                  cfg_scale: $cfg_scale,
                  sample_steps: $sample_steps,
                  negative_prompt: $negative_prompt,
                  image: $image,
                  mask: $mask,
                  stream: true
                } * .')"
    else
        DATA="$(echo -n "${DATA}" | jq \
            --argjson n "${N}" \
            --argjson response_format "\"${RESPONSE_FORMAT}\"" \
            --argjson size "\"${SIZE}\"" \
            --argjson quality "\"${QUALITY}\"" \
            --argjson image "\"${IMAGE}\"" \
            --argjson mask "\"${MASK}\"" \
            '{
                  n: $n,
                  response_format: $response_format,
                  size: $size,
                  quality: $quality,
                  image: $image,
                  mask: $mask,
                  stream: true
                } * .')"
    fi
    echo "Q: ${DATA}" >>"${LOG_FILE}"

    START_TIME=$(date +%s)

    set -e
    if [[ "${SAMPLER}" != "null" ]]; then
        if [[ -n "${MASK}" ]]; then
            while IFS= read -r LINE; do
                if ! parse; then
                    break
                fi
            done < <(curl \
                --silent \
                --no-buffer \
                --request POST \
                --url "${API_URL}/v1/images/edits" \
                --form "prompt=${PROMPT}" \
                --form "n=${N}" \
                --form "response_format=${RESPONSE_FORMAT}" \
                --form "size=${SIZE}" \
                --form "sampler=${SAMPLER}" \
                --form "seed=${SEED}" \
                --form "cfg_scale=${CFG_SCALE}" \
                --form "sample_steps=${SAMPLE_STEPS}" \
                --form "negative_prompt=${NEGATIVE_PROMPT}" \
                --form "image=@${IMAGE}" \
                --form "mask=@${MASK}" \
                --form "stream=true")
        else
            while IFS= read -r LINE; do
                if ! parse; then
                    break
                fi
            done < <(curl \
                --silent \
                --no-buffer \
                --request POST \
                --url "${API_URL}/v1/images/edits" \
                --form "prompt=${PROMPT}" \
                --form "n=${N}" \
                --form "response_format=${RESPONSE_FORMAT}" \
                --form "size=${SIZE}" \
                --form "sampler=${SAMPLER}" \
                --form "seed=${SEED}" \
                --form "cfg_scale=${CFG_SCALE}" \
                --form "sample_steps=${SAMPLE_STEPS}" \
                --form "negative_prompt=${NEGATIVE_PROMPT}" \
                --form "image=@${IMAGE}" \
                --form "stream=true")
        fi
    elif [[ -n "${MASK}" ]]; then
        while IFS= read -r LINE; do
            if ! parse; then
                break
            fi
        done < <(curl \
            --silent \
            --no-buffer \
            --request POST \
            --url "${API_URL}/v1/images/edits" \
            --form "prompt=${PROMPT}" \
            --form "n=${N}" \
            --form "response_format=${RESPONSE_FORMAT}" \
            --form "size=${SIZE}" \
            --form "quality=${QUALITY}" \
            --form "image=@${IMAGE}" \
            --form "mask=@${MASK}" \
            --form "stream=true")
    else
        while IFS= read -r LINE; do
            if ! parse; then
                break
            fi
        done < <(curl \
            --silent \
            --no-buffer \
            --request POST \
            --url "${API_URL}/v1/images/edits" \
            --form "prompt=${PROMPT}" \
            --form "n=${N}" \
            --form "response_format=${RESPONSE_FORMAT}" \
            --form "size=${SIZE}" \
            --form "quality=${QUALITY}" \
            --form "image=@${IMAGE}" \
            --form "stream=true")
    fi
    set +e

    rm -f /tmp/image_edit_*.json
    printf "\n"
}

echo "====================================================="
echo "LOG_FILE          : ${LOG_FILE}"
echo "API_URL           : ${API_URL}"
echo "N                 : ${N}"
echo "RESPONSE_FORMAT   : ${RESPONSE_FORMAT}"
echo "SIZE              : ${SIZE}"
echo "QUALITY           : ${QUALITY}"
echo "IMAGE             : ${IMAGE}"
echo "MASK              : ${MASK}"
echo "SAMPLER           : ${SAMPLER} // OVERRIDE \"QUALITY\" and \"STYLE\" IF NOT NULL, ONE OF [euler_a, euler, heun, dpm2, dpm++2s_a, dpm++2mv2, ipndm, ipndm_v, lcm]"
echo "SEED              : ${SEED} // AVAILABLE FOR SAMPLER"
echo "CFG_SCALE         : ${CFG_SCALE} // AVAILABLE FOR SAMPLER"
echo "SAMPLE_STEPS      : ${SAMPLE_STEPS} // AVAILABLE FOR SAMPLER"
echo "NEGATIVE_PROMPT   : ${NEGATIVE_PROMPT} // AVAILABLE FOR SAMPLER"
printf "=====================================================\n\n"

if [[ -f "${LOG_FILE}" ]]; then
    : >"${LOG_FILE}"
fi
if [[ ! -f "${LOG_FILE}" ]]; then
    touch "${LOG_FILE}"
fi

if [[ "${#@}" -ge 1 ]]; then
    echo "> ${*}"
    image_edit "${*}"
else
    while true; do
        read -r -e -p "> " QUESTION
        image_edit "${QUESTION}"
    done
fi
