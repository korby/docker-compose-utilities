#!/bin/bash
models_path=~/Work/docker-models
model="docker-compose.yml"
port="[0-9]"

echo "Stopping containers if some run here..."
docker-compose stop

if [ "$(uname)" == "Darwin" ]; then
	sed_compat=" \"\" "
else
	sed_compat=""
fi



if [ -f ./$model ]; then
	read -p "File $model already exists, do you want to override it ? [y,N] " resp
	if [ $resp != "y" ]; then echo "Exiting..."; exit; fi
fi

cp $models_path"/"$model ./



function is_used() {
	if [ "$(uname)" == "Darwin" ]; then
		port_used=`netstat -anv | awk 'NR>2{print $4}' | grep -E '\.'$port | sed 's/.*\.//' | sort -n | uniq`
	else
		port_used=`netstat -lnt | awk 'NR>2{print $4}' | grep -E '0.0.0.0:$port' | sed 's/.*://' | sort -n | uniq`
	fi

	port=$1
	res="n"
	for i in ${port_used[@]}
	do
		if [ "$i" == ${port} ]; then
	    	res="y"; break;
	    fi
	done
	echo $res
}


function get_next_free_port() {
	port=$1

	#si le dernier chiffre est 0, on le retire
	if [ "${port:(${#port}-1):1}" == "0" ]; then
		port=$(echo $port | sed 's/.$//')
	fi
	limit="10000"
	counter=1
	while [  $counter -lt $limit ]; do
             newport=$port"$counter"
             if [ "$(is_used $newport)" == "n" ]; then
             	break;
             fi
             
        let counter=counter+1
    done

    echo $newport
	
}

ports_wanted=$(grep -A3 "ports" $model | grep "[0-9]" | cut -c12-25 | sed 's/"//' | cut -d':' -f1)

for port in $ports_wanted; do
	if [ "$(is_used $port)" == "y" ]; then
		if [ "$port" == "80" ]; then
			read -p "Do you want to stop the container running on port 80 ? [y,N] " resp
	    	if [ $resp == "y" ]; then docker stop $(docker ps |grep ":80->" | cut -d " " -f1); fi
		fi
	fi

	if [ "$(is_used $port)" == "y" ]; then
		newport=$(get_next_free_port $port)
		echo $port" is used, replacing with: "$newport
		sed -i $sed_compat"s/\"$port:/\"$newport:/" $model
	fi
done

read -p "Wich domain for vhost ?"$'\n' domain
sed -i $sed_compat"s/- WEBSITE_HOST=domain/- WEBSITE_HOST=$domain/" $model

sed -i $sed_compat"s/- CERTIFICAT_CNAME=domain/- CERTIFICAT_CNAME=$domain/" $model

read -p "Do you want to add 127.0.0.1 $domain to your hosts file ? [y,N] " resp
if [ $resp != "y" ]; then 
	echo "Ok don't touch hosts..."; 
else
	host_file="/etc/hosts"
	(sudo echo "127.0.0.1 $domain" && sudo cat $host_file) > temp && sudo mv temp $host_file
fi

# WORDPRESS
if [ -f "wp-config.php" ]; then
	echo "Wordpress detected, changing wp-config.php values..."
	defined_vars=`php -r 'echo str_replace("define", "\ndefine",php_strip_whitespace("wp-config.php"));'`
	dbh=`echo "$defined_vars" |grep "DB_HOST" | cut -d, -f2 | cut -d"'" -f2`
	dbn=`echo "$defined_vars" |grep "DB_NAME" | cut -d, -f2 | cut -d"'" -f2`
	dbu=`echo "$defined_vars" |grep "DB_USER" | cut -d, -f2 | cut -d"'" -f2`
	dbp=`echo "$defined_vars" |grep "DB_PASSWORD" | cut -d, -f2 | cut -d"'" -f2`
	
	sed -i $sed_compat"s/$dbh/db/" wp-config.php
	sed -i $sed_compat"s/$dbn/website/" wp-config.php
	sed -i $sed_compat"s/$dbu/root/" wp-config.php
	sed -i $sed_compat"s/$dbp//" wp-config.php

fi

echo -e "Now starting docker...\n"

docker-compose up -d

mysql_container=`basename $(pwd) | sed "s/_//g"`
echo '""""""""""""""""'
echo "Now you can import your mysql dump :"
echo ""
echo "docker exec -i "$mysql_container"_db_1 mysql website < ./dump.sql"
echo '""""""""""""""""'

: <<'COMMENT'
TODO
Changer les params dans wordpress (db host etc.)
COMMENT
