#!/usr/bin/env bash

# -- Set Variables

AAP_XY_VERSION=${AAP_XY_VERSION:-2.6}
AAP_XY=$(echo $AAP_XY_VERSION | sed -e 's/\.//g')

# -- General replaces section

replacements=(
    RELATED_IMAGE_GALAXY:RELATED_IMAGE_HUB
    Galaxy:AutomationHub
    galaxy_ansible_com_galaxy:automationhub_ansible_com_automationhub
    galaxy.ansible.com:automationhub.ansible.com
)

# Replace in roles files; settings configmap is intentionally left out to keep settings in tact

for row in "${replacements[@]}"; do
    upstream="$(echo $row | cut -d: -f1)";
    downstream="$(echo $row | cut -d: -f2)";
    find ./roles ./playbooks -type f -name '*' \
      -not -path '*.md' \
	    -exec sed -i -e "s/${upstream}/${downstream}/g" {} \;
done

# Replace in watches.yaml

for row in "${replacements[@]}"; do
    upstream="$(echo $row | cut -d: -f1)";
    downstream="$(echo $row | cut -d: -f2)";
    sed -i -e "s/${upstream}/${downstream}/g" ./watches.yaml ;
done

# -- Replace deployment_type

sed -i -e "s/galaxy/automationhub/g" ./roles/backup/vars/main.yml \
                                   ./roles/backup/templates/event.yaml.j2 \
                                   ./roles/common/defaults/main.yml \
                                   ./roles/galaxy-worker/defaults/main.yml \
                                   ./roles/postgres/defaults/main.yml \
                                   ./roles/restore/vars/main.yml ;

#    static_root for galaxy is different from automationhub

sed -i -e "s|static_root: /app/galaxy_ng/app/static/|static_root: /var/lib/operator/static/|g" ./playbooks/galaxy.yaml ;

# -- Replace in manifest files

replacements=(
    RELATED_IMAGE_GALAXY:RELATED_IMAGE_HUB
)

for row in "${replacements[@]}"; do
    upstream="$(echo $row | cut -d: -f1)";
    downstream="$(echo $row | cut -d: -f2)";
    sed -i -e "s/${upstream}/${downstream}/g" ./config/manifests/bases/galaxy-operator.clusterserviceversion.yaml \
                                              ./config/manager/manager.yaml ;
done

# -- Replace default-container

sed -i '/default-container:/s/galaxy-manager/automation-hub-manager/' \
                                              ./config/manifests/bases/galaxy-operator.clusterserviceversion.yaml \
                                              ./config/manager/manager.yaml ;

# -- Replace Service Account name

files=(
    config/manifests/bases/galaxy-operator.clusterserviceversion.yaml
    roles/common/defaults/main.yml
    config/rbac/role.yaml
)

for file in "${files[@]}"; do
   sed -i -e "s/galaxy-operator-sa/automationhub-operator-sa/g" ${file};
done

# -- Swap out postgres data path
#  /var/lib/postgresql/data/pgdata/PG_VERSION      < Upstream postgres path
#  /var/lib/pgsql/data/userdata/PG_VERSION         < Downstream postgresql-12 path (and 13)

sed -i -e "s/\/var\/lib\/postgresql\/data\/pgdata/\/var\/lib\/pgsql\/data\/userdata/g" ./roles/postgres/defaults/main.yml

# -- Set default ingress_type to Route
# Set default used by deployment templates

files=(
    roles/galaxy-api/defaults/main.yml
    roles/galaxy-content/defaults/main.yml
    roles/galaxy-status/defaults/main.yml
    roles/galaxy-web/defaults/main.yml
)

for file in "${files[@]}"; do
    sed -i -e "s/ingress_type:\ none/ingress_type:\ Route/g" ${file};
done

# Set default in manifest and crd files

files=(
    config/crd/bases/galaxy_v1beta1_galaxy_crd.yaml
)
for file in "${files[@]}"; do
  if ! grep -qF 'default: Route' ${file}; then
    sed -i -e "/ingress_type:/a \\
                default:\ Route" ${file};
  fi
done

# -- Set Fully Qualified Domain Names for k8s modules

find ./roles ./playbooks -type f -name '*.y*ml' \
  -exec sed -i -e "s/ k8s\(.*\):/ kubernetes.core.k8s\1:/g" {} \;

# Use operator_sdk.utils.k8s_status

find ./roles ./playbooks -type f -name '*.y*ml' \
  -exec sed -i -e " s/ kubernetes.core.k8s_status:/ operator_sdk.util.k8s_status:/g" {} \;

# Replace annotations for ansible signing

sed -i -e 's|app.kubernetes.io/managed-by=galaxy-operator|"app.kubernetes.io/managed-by={{\ deployment_type\ }}-operator"|g' ./roles/galaxy-api/tasks/main.yml;

# Update entrypoint script directory path in ./roles/common/vars/main.yml _entrypoint_dir: /env/bin
sed -i -e 's|_entrypoint_dir: /venv/bin|_entrypoint_dir: /usr/bin|g' ./roles/common/vars/main.yml

sed -i -e "s|gating_version:.*|gating_version: '4.10.0'|g" ./roles/common/vars/main.yml

# Update pulpcore-manager binary location

sed -i -e 's|/usr/local/bin/pulpcore-manager|/usr/bin/pulpcore-manager|g' ./roles/galaxy-api/tasks/main.yml

# TODO: May need to make changes upstream to create a Service Account in the namespace Hub is deployed to.
# This way, users will still be able to deploy the hub-operator to the operators namespace,
# and create a AutomationHub CR in the hub namespace

# TODO: Set this as a 'suggested' setting via alm-examples in a way that it gets used in the AAP wrapped operator

# Uneeded because it is still upstream
