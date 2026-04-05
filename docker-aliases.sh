# =========================
# Docker - Basic
# =========================
alias d='docker'
alias dc='docker compose'

# =========================
# Containers
# =========================
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dstart='docker start'
alias dstop='docker stop'
alias drestart='docker restart'
alias drm='docker rm'
alias drmf='docker rm -f'

# =========================
# Images
# =========================
alias di='docker images'
alias drmi='docker rmi'
alias dbuild='docker build -t'

# =========================
# Logs & Exec
# =========================
alias dlogs='docker logs -f'
alias dexec='docker exec -it'

# =========================
# Cleanup
# =========================
alias dprune='docker system prune -f'
alias dprunea='docker system prune -a -f'

# =========================
# Compose
# =========================
alias dcup='docker compose up'
alias dcupd='docker compose up -d'
alias dcdown='docker compose down'
alias dcb='docker compose build'
alias dclogs='docker compose logs -f'

# =========================
# Quick Helpers (Functions)
# =========================

# Enter container with bash/sh fallback
denter() {
  docker exec -it "$1" bash 2>/dev/null || docker exec -it "$1" sh
}

# Stop & remove all containers
dclean() {
  docker rm -f $(docker ps -aq) 2>/dev/null
}

# Remove all images
dcleani() {
  docker rmi -f $(docker images -q) 2>/dev/null
}

# Show container IP
dip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}