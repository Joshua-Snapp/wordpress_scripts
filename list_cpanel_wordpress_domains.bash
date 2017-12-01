#!/usr/bin/env bash

# It seems that when the nrpe service is restarted, sometimes the TERM
# environment variable ends up being set to "dumb". When the nrpe user runs a
# check written in Bash, it reports "NRPE: Unable to read output". Setting
# TERM='xterm' in the script ensures that the script will have the correct
# environment to run.
TERM='xterm'

#Use bash's builtin error checking.
set -o errexit

##The trap will make sure that the script exits cleanly, even if a SIGHUP, SIGINT or SIGTERM is received.
trap error_exit SIGHUP SIGINT SIGTERM

error_exit() {
  #Function "error_exit" is used to exit cleanly while providing an error code.
  #Display error message and exit
  echo -e "\n\n${functiontitle}: ${1:-"Unknown Error"}" 1>&2
  if [[ ${functiontitle} == 'dump_array_data_to_cache_files' ]]
  then
    for i in ${wp_info_location} ${site_type_location}
    do
      if [[ -f ${i} ]]
      then
        rm -f ${i}
      fi
    done
  fi
  exit 1
}

script="${0}"

addon_list_location="/tmp/addon_list_`hostname -s`.json"
format='--format=csv'
wpconfig_file_location="/tmp/list_of_wpconfig_file_locations_`hostname -s`.txt"
results_location="/tmp/site_list_results_`hostname -s`.csv"
site_type_location="/tmp/site_type_results_`hostname -s`.txt"
site_list_fields='--fields=url,registered,last_updated,deleted'
wp_info_location="/tmp/wp_info_`hostname -s`.txt"

remove_existing_results_file() {
  functiontitle='remove_existing_results_file'
  set +e
  for i in ${results_location} ${addon_list_location}
  do
    if [[ -f ${i} ]]
    then
      rm -f ${i}
    fi
  done
  set -e
}

ask_user_about_existing_cached_array_data() {
  functiontitle='ask_user_about_existing_cached_array_data'
if [[ -f ${wp_info_location} ]] && [[ -f ${site_type_location} ]]
then
  echo -e 'Both cache files found. Do you want to reuse cached array data?'
  echo -e 'Respond yes to reuse or no to delete cache files.'
  read -p 'y/n: ' will_cache_files_be_used
  while [[ ${will_cache_files_be_used} != 'y' ]] && [[ ${will_cache_files_be_used} != 'n' ]]
  do
    echo -e 'Response must be either y or n.'
    read -p 'y/n: ' will_cache_files_be_used
  done
else
  will_cache_files_be_used='n'
  for i in ${wp_info_location} ${site_type_location} ${wpconfig_file_location}
  do
    if [[ -f ${i} ]]
    then
      rm -f ${i}
    fi
  done
fi
}

find_wpconfig_files_in_homedir() {
  functiontitle='find_wpconfig_files_in_homedir'
  wpconfig_path=(`find /home/ -type f -name 'wp-config.php' -not -path '/home/virtfs/*' -printf '%h\n' | sort`)
  for i in "${wpconfig_path[@]}"
  do
    wp_info_array[${i}]="`stat -c "%U" ${i}`"
  done
}

identify_site_type() {
  functiontitle='identify_site_type'
  set +e
  for i in ${!wp_info_array[@]}
  do
    sudo -u ${wp_info_array[${i}]} -- wp --path=${i} core is-installed --network &>/dev/null
    if [[ $? == 0 ]]
    then
      site_type_array[${i}]="multisite"
    else
      sudo -u ${wp_info_array[${i}]} -- wp --path=${i} core is-installed &>/dev/null
      if [[ $? == 0 ]]
      then
        site_type_array[${i}]="singlesite"
      else
        site_type_array[${i}]="no_wordpress_site"
      fi
    fi
  done
  set -e
}

dump_array_data_to_cache_files() {
  functiontitle='dump_array_data_to_cache_files'
  declare -p wpconfig_path > ${wpconfig_file_location}
  declare -p wp_info_array > ${wp_info_location}
  declare -p site_type_array > ${site_type_location}
}

list_single_and_multi_site_data() {
  functiontitle='list_single_and_multi_site_data'
  for i in ${!wpconfig_path[@]}
  do
    if [[ ${site_type_array[${wpconfig_path[${i}]}]} == 'singlesite' ]]
    then
      echo -e "`hostname -s`,${site_type_array[${wpconfig_path[${i}]}]},${wp_info_array[${wpconfig_path[${i}]}]},${wpconfig_path[${i}]}" >> ${results_location}
      sudo -u ${wp_info_array[${wpconfig_path[${i}]}]} -- wp --path=${wpconfig_path[${i}]} option get siteurl 2> /dev/null >> ${results_location}
    elif [[ ${site_type_array[${wpconfig_path[${i}]}]} == 'multisite' ]]
    then
      echo -e "`hostname -s`,${site_type_array[${wpconfig_path[${i}]}]},${wp_info_array[${wpconfig_path[${i}]}]},${wpconfig_path[${i}]}" >> ${results_location}
      sudo -u ${wp_info_array[${wpconfig_path[${i}]}]} -- wp --path=${wpconfig_path[${i}]} site list ${site_list_fields} ${format} 2> /dev/null >> ${results_location}
    fi
  done
}

list_cpanel_account_users() {
  functiontitle='list_cpanel_account_users'
  cpanel_user_array=(`whmapi1 listaccts want user | awk '/user/ {print $2}' | sort`)
}

list_addon_domains_per_user() {
  functiontitle='list_addon_domains_per_user'
for i in ${cpanel_user_array[@]}
do
  echo -e "\n${i}" >> ${addon_list_location} && uapi --user=${i} DomainInfo list_domains >> ${addon_list_location};
done
}

cleanup_results_files() {
  functiontitle='cleanup_results_files'
  sed -i '/^http/s/^/,,,,/' ${results_location}
  sed -i '/^,,,,http\|web0.cp,\|^Server/!d' ${results_location}
  sed -i '/^web0\|^,,,,http\|^Server/!s/^.\+\(web0.cp,\)/\1/' ${results_location}
  sed -i '1i Server,Site Type,cPanel User,Path to wpconfig.php,URL,Registered,Last Updated,Deleted' ${results_location}
}

remove_existing_results_file
ask_user_about_existing_cached_array_data
if [[ ${will_cache_files_be_used} == 'y' ]]
then
  source -- ${wpconfig_file_location}
  source -- ${wp_info_location}
  source -- ${site_type_location}
elif [[ ${will_cache_files_be_used} == 'n' ]]
then
  declare -A wp_info_array
  declare -A site_type_array
  find_wpconfig_files_in_homedir
  identify_site_type
  dump_array_data_to_cache_files
fi
set +e
list_single_and_multi_site_data
set -e
list_cpanel_account_users
list_addon_domains_per_user
cleanup_results_files
