#!/bin/bash -x

echo "================================================================================="
echo "Clean Tempest's own objects..."
ROLE_IDS=$(keystone role-list | grep '^| [a-z0-9]' | grep -v ' name ' | awk '{print $2}')
USER_IDS=$(keystone user-list | grep 'example\.com' | grep -v ' name ' | awk '{print $2}')

### CLEANING NETWORKS ###
# TODO: define tempest naming schema - these object names is incorrect for tempest
# for r in $(quantum router-list | awk '/t[12]_router/ {print $2}'); do for sn in $(quantum subnet-list | awk '/_net/ {print $2}'); do quantum router-interface-delete $r $sn; done; done
# quantum subnet-list | awk '/_net/ {print $2}' | xargs -n1 -i% quantum subnet-delete %
# quantum net-list | awk '/_net/ {print $2}' | xargs -n1 -i% quantum net-delete %
# quantum router-list | awk '/t[12]_router/ {print $2}' | xargs -n1 -i% quantum router-delete %

TENANT_IDS=$(keystone tenant-list | grep -E '\-tenant|tenant\-' | grep -v ' name ' | awk '{print $2}')
for t in $TENANT_IDS; do
    for u in $USER_IDS; do
        for r in $ROLE_IDS; do
            keystone user-role-remove --user-id $u --role-id $r --tenant-id $t
        done
    done
done
for u in $USER_IDS; do keystone user-delete $u; done
for t in $TENANT_IDS; do keystone tenant-delete $t; done
nova list --all-tenants 1 | grep 'server' | grep -iv ' Name ' | awk '{print $2}' | xargs -n1 -i% nova delete %

