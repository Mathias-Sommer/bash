#!/usr/bin/env bash
set -e

WEB_ROOT="/var/www/html"
DOMAINS=()
REPO=""
SITE_NAME=""
CERTBOT_EMAIL=""
EFF_EMAIL_FLAG="--no-eff-email" 

# help section
print_help() {
  echo "Usage:"
  echo "  ./nginx-setup.sh --repo <git-url> --domain <domain> [--domain <domain>] --email <email> [options]"
  echo ""
  echo "You are highly recommended to run the following command before this script is executed:"
  echo "sudo apt update && sudo apt upgrade"
  echo ""
  echo "Required options:"
  echo "  --repo          Git repository URL for site content"
  echo "  --domain        Domain name (can be used multiple times)"
  echo "  --email         Email for Let's Encrypt / Certbot"
  echo ""
  echo "Optional options:"
  echo "  --site-name     Nginx site name (default: first domain)"
  echo "  --web-root      Web root directory (default: /var/www/html)"
  echo "  --eff-email     Allow sharing email with EFF (default: disabled)"
  echo "  --help          Show this help and exit"
  echo ""
  echo "Certbot behavior:"
  echo "  - Runs non-interactively"
  echo "  - Automatically agrees to Let's Encrypt Terms of Service"
  echo "  - Uses --no-eff-email unless --eff-email is explicitly set"
}

# argument parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --domain)
      DOMAINS+=("$2")
      shift 2
      ;;
    --email)
      CERTBOT_EMAIL="$2"
      shift 2
      ;;
    --site-name)
      SITE_NAME="$2"
      shift 2
      ;;
    --web-root)
      WEB_ROOT="$2"
      shift 2
      ;;
    --eff-email)
      EFF_EMAIL_FLAG="--eff-email"
      shift
      ;;
    --help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo ""
      print_help
      exit 1
      ;;
  esac
done

# argument validation
if [[ -z "$REPO" ]]; then
  echo "ERROR: --repo is required"
  exit 1
fi

if [[ ${#DOMAINS[@]} -eq 0 ]]; then
  echo "ERROR: At least one --domain is required"
  exit 1
fi

if [[ -z "$CERTBOT_EMAIL" ]]; then
  echo "ERROR: --email is required"
  exit 1
fi

if [[ -z "$SITE_NAME" ]]; then
  SITE_NAME="${DOMAINS[0]}"
fi

SERVER_NAMES="${DOMAINS[*]}"

# system setup
sudo apt install -y nginx git certbot python3-certbot-nginx

# web root setup
sudo mkdir -p "$WEB_ROOT"
sudo chown -R "$USER:$USER" "$WEB_ROOT"
sudo chmod -R 755 "$WEB_ROOT"
rm -rf "$WEB_ROOT"/*

git clone "$REPO" site-tmp
mv site-tmp/* "$WEB_ROOT"
rm -rf site-tmp

# nginx config
sudo rm -f /etc/nginx/sites-available/default
sudo rm -f /etc/nginx/sites-enabled/default

sudo tee "/etc/nginx/sites-available/$SITE_NAME" > /dev/null <<EOF
server {

    server_name $SERVER_NAMES;

    root $WEB_ROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

sudo ln -sf "/etc/nginx/sites-available/$SITE_NAME" \
           "/etc/nginx/sites-enabled/$SITE_NAME"

sudo nginx -t
sudo systemctl reload nginx

# firewall
sudo ufw allow "OpenSSH"
sudo ufw allow "Nginx Full"
sudo ufw --force enable

# ==========================================================
# Certbot (non-interactive)
# ==========================================================
CERTBOT_DOMAINS=()
for d in "${DOMAINS[@]}"; do
  CERTBOT_DOMAINS+=("-d" "$d")
done

sudo certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email "$CERTBOT_EMAIL" \
  $EFF_EMAIL_FLAG \
  "${CERTBOT_DOMAINS[@]}"

sudo certbot renew --dry-run --non-interactive

# script done
echo ""
echo "Deployment complete"
echo "[~] Site name : $SITE_NAME"
echo "[~] Domains   : $SERVER_NAMES"
echo "[~] Web root  : $WEB_ROOT"
echo "[~] EFF email : ${EFF_EMAIL_FLAG#--}"