function cluster_meta()
{
	local name="${1}"
	tiup cluster list 2>/dev/null | \
		{ grep -v 'PrivateKey$' || test $? = 1; } | \
		{ grep -v '\-\-\-\-\-\-\-$' || test $? = 1; } | \
		{ grep "^${name} " || test $? = 1; }
}

function must_cluster_version()
{
	local name="${1}"
	local version=`tiup cluster display "${name}" --version 2>/dev/null`
	if [ $? != 0 ]; then
		echo "[:(] no such cluster exists, please ensure the cluster name '${name}'"
		exit 1
	fi
	echo "${version}"
}

function cluster_exist()
{
	local name="${1}"
	local meta=`cluster_meta ${name}`
	if [ -z "${meta}" ]; then
		echo "false"
	else
		echo "true"
	fi
}

function must_cluster_exist()
{
	local name="${1}"
	meta=`cluster_meta ${name}`
	if [ -z "${meta}" ]; then
		echo "[:(] cluster name '${name}' not exists" >&2
		exit 1
	fi
}

# TODO: this is a mess, split it to multi functions
# export: $pri_key, $user, $cnt, $hosts, $deploy_dirs, $data_dirs
function get_instance_info()
{
	local env="${1}"
	local check_stopped="${2}"

	local name=`must_env_val "${env}" 'tidb.cluster'`

	set +e
	local statuses=`tiup cluster display "${name}" 2>/dev/null`
	set -e
	local instances=`echo "${statuses}" | awk '{if ($2=="pd" || $2=="tikv" || $2=="tiflash" || $2=="tiflash-learner") print $0}'`
	if [ -z "${instances}" ]; then
		tiup cluster display "${name}"
		echo "[:(] can't find storage instances (pd/tikv/tiflash)" >&2
		exit 1
	fi
	cnt=`echo "${instances}" | wc -l`

	# TODO: use this key for ssh
	set +e
	pri_key=`tiup cluster list 2>/dev/null | awk '{if ($1=="'${name}'") print $NF}'`
	set -e

	# TODO: get this from tiup yaml file. and other values like ssh-port
	user='tidb'

	if [ "${check_stopped}" != 'false' ]; then
		local ups=`echo "${instances}" | awk '{print $6}' | { grep 'Up' || test $? = 1; }`
		if [ ! -z "${ups}" ]; then
			echo "[:(] cluster not fully stop, can't backup" >&2
			exit 1
		fi
	fi

	hosts=(`echo "${instances}" | awk '{print $3}'`)
	deploy_dirs=(`echo "${instances}" | awk '{print $NF}'`)
	data_dirs=(`echo "${instances}" | awk '{print $(NF-1)}'`)

	if [ "${#hosts[@]}" != "${#deploy_dirs[@]}" ]; then
		echo "[:(] hosts count != dirs count, string parsing failed" >&2
		exit 1
	fi
	if [ "${#hosts[@]}" == '0' ]; then
		echo "[:(] hosts count == 0, string parsing failed" >&2
		exit 1
	fi
}

function cluster_tidbs()
{
	local name="${1}"
	set +e
	local tidbs=`tiup cluster display "${name}" 2>/dev/null | \
		{ grep '\-\-\-\-\-\-\-$' -A 9999 || test $? = 1; } | \
		awk '{if ($2=="tidb") print $1}'`
	set -e
	echo "${tidbs}"
}

function must_cluster_tidbs()
{
	local name="${1}"
	local tidbs=`cluster_tidbs "${name}"`
	if [ -z "${tidbs}" ]; then
		echo "[:(] no tidb found in cluster '${name}'" >&2
		exit 1
	fi
	echo "${tidbs}"
}

function cluster_tikvs()
{
	local name="${1}"
	set +e
	local tikvs=`tiup cluster display "${name}" 2>/dev/null | \
		{ grep '\-\-\-\-\-\-\-$' -A 9999 || test $? = 1; } | \
		awk '{if ($2=="tikv") print $1}'`
	set -e
	echo "${tikvs}"
}

function must_cluster_tikvs()
{
	local name="${1}"
	local tikvs=`cluster_tikvs "${name}"`
	if [ -z "${tikvs}" ]; then
		echo "[:(] no tikv found in cluster '${name}'" >&2
		exit 1
	fi
	echo "${tikvs}"
}

function cluster_tiflashs()
{
	local name="${1}"
	set +e
	local tiflashs=`tiup cluster display "${name}" 2>/dev/null | \
		{ grep '\-\-\-\-\-\-\-$' -A 9999 || test $? = 1; } | \
		awk '{if ($2=="tiflash") print $1}'`
	set -e
	echo "${tiflashs}"
}

function must_cluster_tiflashs()
{
	local name="${1}"
	local tiflashs=`cluster_tiflashs "${name}"`
	if [ -z "${tiflashs}" ]; then
		echo "[:(] no tiflash found in cluster '${name}'" >&2
		exit 1
	fi
	echo "${tiflashs}"
}

function must_cluster_pd()
{
	local name="${1}"
	set +e
	local pd=`tiup cluster display "${name}" 2>/dev/null | \
		{ grep '\-\-\-\-\-\-\-$' -A 9999 || test $? = 1; } | \
		awk '{if ($2=="pd") print $1}'`
	set -e
	if [ -z "${pd}" ]; then
		echo "[:(] no pd found in cluster '${name}'" >&2
		exit 1
	fi
	echo "${pd}"
}

function must_pd_addr()
{
	local name="${1}"
	set +e
	local pd=`tiup cluster display "${name}" 2>/dev/null | \
		{ grep '\-\-\-\-\-\-\-$' -A 9999 || test $? = 1; } | \
		awk '{if ($2=="pd" && $6=="Up|L|UI") print $3":"$4}'`
	set -e
	if [ -z "${pd}" ]; then
		echo "[:(] no pd found in cluster '${name}'" >&2
		exit 1
	fi
	echo "${pd%/*}"
}

function must_pd_leader_id()
{
	local name="${1}"
	set +e
	local pd=`tiup cluster display "${name}" -R pd --json 2>/dev/null | \
		jq --raw-output ".instances[]|select(.status | contains(\"L\"))|.id" 2>/dev/null`
	set -e
	if [ -z "${pd}" ]; then
		set +e
		local host_port=`tiup cluster display "${name}" -R pd | grep '\-\-\-' -A 99999 | grep 'L' | awk '{if ($2=="pd") print $3,$4}'`
		set -e
		if [ ! -z "${host_port}" ]; then
			local pd_host=`echo "${host_port}" | awk '{print $1}'`
			local pd_port=`echo "${host_port}" | awk '{print $2}' | awk -F '/' '{print $1}'`
			local pd="${pd_host}:${pd_port}"
		fi
	fi
	if [ -z "${pd}" ]; then
		echo "[:(] no pd leader found in cluster '${name}'" >&2
		exit 1
	fi
	echo "${pd}"
}

function must_prometheus_addr()
{
	local name="${1}"
	set +e
	local prom=`tiup cluster display "${name}" 2>/dev/null | \
		{ grep '\-\-\-\-\-\-\-$' -A 9999 || test $? = 1; } | \
		awk '{if ($2=="prometheus") print $3":"$4}'`
	set -e
	if [ -z "${prom}" ]; then
		echo "[:(] no prometheus found in cluster '${name}'" >&2
		exit 1
	fi
	echo "${prom}"
}

function must_store_id()
{
	local pd_leader_id="${1}"
	local version="${2}"
	local address="${3}"

	local store_id=`tiup ctl:${version} pd -u "${pd_leader_id}" store 2>/dev/null|\
		jq --raw-output ".stores[]|select(.store.address==\"${address}\").store.id"`
	if [ -z "${store_id}" ]; then
		echo "[:(] couldn't found the store id of the host '${host}'"
		exit 1
	fi
	echo "${store_id}"
}
