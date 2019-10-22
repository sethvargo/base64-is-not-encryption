# google-project returns the name of the current project, accounting for a
# variety of common environments. If no project is found in any of the common
# places, an error is returned.
google-project() {
  (
    set -Eeuo pipefail

    local project="${PROJECT:-${GOOGLE_PROJECT:-${GOOGLE_CLOUD_PROJECT:-${DEVSHELL_PROJECT_ID:-}}}}"
    if [ -z "${project:-}" ]; then
      echo "Missing project ID. Please set PROJECT, GOOGLE_PROJECT, or"
      echo "GOOGLE_CLOUD_PROJECT to the ID of your project to continue:"
      echo ""
      echo "    export GOOGLE_CLOUD_PROJECT=$(whoami)-foobar123"
      echo ""
      return 127
    fi
    echo "${project}"
  )
}

# google-region returns the region in which resources should be created. This
# variable must be changed before running any commands.
google-region() {
  (
    ZONE="$(google-zone)"
    echo "${ZONE::-2}"
  )
}

google-zone() {
  (
    echo "us-east1-b"
  )
}
