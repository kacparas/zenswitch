#!/bin/sh
# Creates one launcher ("scriptlet") per profile in the Kindle library:
#   /mnt/us/documents/<Name>.sh  -> starts that profile through zenswitch.sh
# Run on the Kindle (e.g. over SSH) after editing profiles.conf:  sh /mnt/us/zenswitch/make-launchers.sh
ZS_HOME="$(CDPATH='' cd "$(dirname "$0")" && pwd -P)"
CONF="${ZS_HOME}/profiles.conf"
DOCS="${1:-/mnt/us/documents}"
[ -f "${CONF}" ] || { echo "no ${CONF} (copy profiles.conf.example)"; exit 1; }
while IFS='|' read -r name rest || [ -n "${name}" ]; do
    case "${name}" in '' | '#'*) continue ;; esac
    name="$(echo "${name}" | tr -d '\r')"
    f="${DOCS}/${name}.sh"
    cat >"${f}" <<EOS
#!/bin/sh
# Name: ${name}
# Author: ZenSwitch
# DontUseFBInk
exec /bin/sh "${ZS_HOME}/zenswitch.sh" --asap "${name}"
EOS
    echo "launcher: ${f}"
done <"${CONF}"
