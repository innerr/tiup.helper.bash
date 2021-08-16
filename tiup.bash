function cluster_meta()
{
	local name="${1}"
	tiup cluster list 2>/dev/null | \
		{ grep -v 'PrivateKey$' || test $? = 1; } | \
		{ grep -v '\-\-\-\-\-\-\-$' || test $? = 1; } | \
		{ grep "^${name} " || test $? = 1; }
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


