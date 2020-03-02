#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then error "PLEASE RE-RUN SCRIPT AS A SUPER USER!"
  echo "\n"
  exit 1
fi

red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
blu=$'\e[1;36m'
mag=$'\e[1;35m'
end=$'\e[0m'

warn () {
  echo "${yel}$1${end}"
}
error () {
  echo "${red}$1${end}"
}
success () {
  echo "${grn}$1${end}"
}
info() {
  echo "${blu}$1${end}"
}

add-loopback-alias() {
  local ip=$1
  info "Adding loopback alias for ip: $ip..."
  ifconfig lo0 $ip alias
  success "Added looback alias for ip: $ip..."
}

enable-firewall-stealth-mode() {
  info "Enabling firewall and stealth mode..."
  /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
  success "Firewall and stealth mode enabled!"
}

add-port-forward-rule() {
  local pf_conf=/etc/pf.conf
  local ip=$1
  local port=$2
  local pf_entry="rdr pass on lo0 inet proto tcp from any to $ip port 443 -> 127.0.0.1 port $port"
  info "Adding port forward rule for $ip:443 -> 127.0.0.1:$port"
  # Delete old entries using this ip address
  sed -i'' -e '/'$''"$ip"'/d' ${pf_conf}
  # Place them under the rdr-anchor statement in the default conf file
  sed -i'' -e '/rdr-anchor "com\.apple\/\*"/a\'$'\n'"$pf_entry"$'\n' ${pf_conf}

  # Reload the altered configuration file
  pfctl -f /etc/pf.conf
  dscacheutil -flushcache

  success "Done!"
}

add-dns-host() {
  local ip=$1
  local host=$2

  info "Adding host $host for ip $ip..."
  # Delete old host (with possibly bad ip)
  sed -i'' -e '/'$''"$host"'/d' /etc/hosts
  # Add new host
  echo "$ip $host" >> /etc/hosts

  # Flush the caches
  sudo killall -HUP mDNSResponder \
  && sudo killall mDNSResponderHelper \
  && sudo dscacheutil -flushcache

  success "Done!"
}

build-env-file() {
  info "Checking for env file..."
  local env_file="${1:-.env}"
  if [ -f ${env_file} ]; then
    success "Env file found! parsing AWS credentials..."
    AWS_ACCESS_KEY_ID=$(cat ${env_file} | grep "AWS_ACCESS_KEY_ID" | cut -d "=" -f2)
    AWS_SECRET_ACCESS_KEY=$(cat ${env_file} | grep "AWS_SECRET_ACCESS_KEY" | cut -d "=" -f2)
  else
    warn "No env file found."
    read -s -p "ENTER YOUR AWS_ACCESS_KEY_ID: " AWS_ACCESS_KEY_ID
    echo "\n"
    read -s -p "ENTER YOUR AWS_SECRET_ACCESS_KEY: " AWS_SECRET_ACCESS_KEY
    echo "\n"
    info "Creating env file..."
  cat << EOF > ${env_file}
# Add environment variables to this file to overwrite ones in your container
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
EOF
  success "Created env file!"
fi
}

install-docker() {
  info "Checking if docker is installed..."
  if ! [ -d /Applications/Docker.app ]; then
    warn "Docker is not installed."
    if ! [ -f ~/Downloads/Docker.dmg ]; then 
      info "Downloading docker..."
      curl https://download.docker.com/mac/stable/Docker.dmg -o ~/Downloads/Docker.dmg
    fi 

    success "Docker is downloaded!"

    info "Mounting docker dmg..."
    if ! [ -d /Volumes/Docker ]; then
      hdiutil attach ~/Downloads/Docker.dmg
    fi

    info "Copying docker contents to Applications directory..."
    cp -R /Volumes/Docker/Docker.app /Applications

    info "Unmounting docker dmg..."
    hdiutil unmount /Volumes/Docker
  fi
  success "Docker is installed!"
}

initialize-docker() {
  install-docker
  info "Checking if docker is running..."
  if ! docker ps -q &> /dev/null; then
    warn "Docker is not running"
    info "Attempting to start docker..."
    open /Applications/Docker.app
    while ! docker stats --no-stream &> /dev/null; do
      info "Waiting for docker daemon to initialize..."
      sleep 1
    done
  fi

  success "Docker is running. Good Work"
}

remove-ssl-certs-from-keychain() {
  info "Removing previous certificate from keychain..."
  sudo security delete-certificate -t -c mkcert || true 
  success "Removed previous certificates..."
}

add-ssl-certs-to-keychain() {
  local root_ca_file="${1:-./ssl/rootCA.pem}"
  while ! [ -f ${root_ca_file} ];
  do
    info "Awaiting ssl certificate authority generation..."
    sleep 2
  done
  info "Adding certificate authority to local keychain..."
  security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ${root_ca_file}
  success "Added certificate authority to keychain!"
}

restart-containers() {
  initialize-docker
  info "running docker-compose down"
  docker-compose down
  info "Logging you into docker hub..."
  docker login 
  success "Logged into docker hub!"
  info "running docker-compose pull"
  docker-compose pull
  info "running docker-compose up"
  docker-compose up --remove-orphans -d
}

aws-cli() {
docker run --rm  \
  -e "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" \
  -e "AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" \
  -e "AWS_DEFAULT_REGION=us-west-2" \
  -v "$(pwd):/project" \
  mesosphere/aws-cli \
  "$@"
}