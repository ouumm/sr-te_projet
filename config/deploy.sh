#!/bin/bash
# deploy.sh - SR-TE Lab OSPF-TE + SR-MPLS + PCE stateful

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}$*${NC}"; }
warn() { echo -e "${YELLOW}   $*${NC}"; }
err()  { echo -e "${RED}  $*${NC}"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPO_INPUT="$SCRIPT_DIR/docker-compose_srte.yml"
TOPO_OUTPUT="$SCRIPT_DIR/docker-compose.yml"
IMAGE="ios-xr/xrd-control-plane:25.3.1"

# Topo Cisco existante qui occupe nos subnets
SANDBOX_TOPO=~/XRd-Sandbox/topologies/segment-routing/docker-compose.yml

echo ""
echo "========================================"
echo "   SR-TE Lab — OSPF-TE + SR-MPLS + PCE"
echo "========================================"
echo "Dossier : $SCRIPT_DIR"
echo ""

# ── STOP topo Cisco segment-routing si elle tourne ───────────────────────────
echo "── Arret de la topo segment-routing du sandbox Cisco..."

if [ -f "$SANDBOX_TOPO" ]; then
    docker-compose --file "$SANDBOX_TOPO" down --volumes 2>/dev/null \
        && ok "segment-routing arrete" \
        || warn "Erreur lors de l'arret de segment-routing (on continue)"
else
    warn "$SANDBOX_TOPO introuvable — on continue"
fi

# ── STOP notre ancienne topo ─────────────────────────────────────────────────
echo ""
echo "── Arret de notre ancienne topo..."

if [ -f "$TOPO_OUTPUT" ]; then
    docker-compose --file "$TOPO_OUTPUT" down --volumes 2>/dev/null \
        && ok "Ancienne topo arretee" \
        || warn "Erreur lors de l'arret (on continue)"
else
    warn "Aucun docker-compose.yml trouve — pas de topo active"
fi

# ── SUPPRIMER CONTAINERS RESIDUELS ───────────────────────────────────────────
for name in router1 router2 router3 router4 pce pc1 pc2 xrd-1 xrd-2 xrd-3 xrd-4 xrd-5 xrd-6 xrd-7 xrd-8 source dest; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        echo "   Suppression container residuel : $name"
        docker rm -f "$name" 2>/dev/null || true
    fi
done

# ── NETTOYAGE RESEAUX ────────────────────────────────────────────────────────
echo ""
echo "── Nettoyage des reseaux Docker residuels..."

# Supprimer les reseaux segment-routing du sandbox Cisco
for net in \
    segment-routing_source-xrd-1 \
    segment-routing_xrd-2-dest \
    segment-routing_mgmt \
    config_pc1-router1 \
    config_router4-pc2 \
    srte_pc1-router1 \
    srte_router4-pc2; do
    docker network rm "$net" 2>/dev/null && echo "   $net supprime" || true
done

# Supprimer aussi tous les reseaux xrd-X-giY (links L2 de la topo Cisco)
docker network ls --format '{{.Name}}' | grep -E "^xrd-[0-9]+-gi" | while read net; do
    docker network rm "$net" 2>/dev/null && echo "   $net supprime" || true
done

# Prune final
docker network prune -f 2>/dev/null && ok "docker network prune OK" || true
ok "Nettoyage termine"

# Afficher ce qui reste (diagnostic)
echo ""
echo "── Reseaux restants apres nettoyage :"
docker network ls --format "   {{.Name}}"

# ── VERIFICATION DES FICHIERS ────────────────────────────────────────────────
echo ""
echo "── Verification des fichiers dans $SCRIPT_DIR..."

REQUIRED=(
    "docker-compose_srte.yml"
    "router1-startup.cfg"
    "router2-startup.cfg"
    "router3-startup.cfg"
    "router4-startup.cfg"
    "pce-startup.cfg"
)

ALL_OK=true
for f in "${REQUIRED[@]}"; do
    if [ -f "$SCRIPT_DIR/$f" ]; then
        ok "$f"
    else
        echo -e "${RED}  MANQUANT : $f${NC}"
        ALL_OK=false
    fi
done

[ "$ALL_OK" = true ] || err "Fichiers manquants dans $SCRIPT_DIR"
ok "Tous les fichiers sont presents"

cd "$SCRIPT_DIR"

# ── GENERATION docker-compose.yml ────────────────────────────────────────────
echo ""
echo "- Generation docker-compose.yml via xr-compose..."
xr-compose \
    --input-file  "$TOPO_INPUT" \
    --output-file "$TOPO_OUTPUT" \
    --image       "$IMAGE"
ok "docker-compose.yml genere"

# - FIX SUBNET EN CONFLIT (genere par xr-compose) ───────────────────────────
echo ""
echo "── Correction des subnets en conflit..."
if grep -q "172.18.0.0/16" "$TOPO_OUTPUT"; then
    sed -i.bak 's|172\.18\.0\.0/16|172.30.0.0/16|g' "$TOPO_OUTPUT"
    ok "172.18.0.0/16 -> 172.30.0.0/16"
else
    ok "Pas de subnet 172.18.0.0/16 — rien a changer"
fi

# - LANCEMENT ────────────────────────────────────────────────────────────────
echo ""
echo "- Demarrage des containers..."
docker-compose --file "$TOPO_OUTPUT" up --detach
ok "Containers lances"

# ── ATTENTE BOOT ─────────────────────────────────────────────────────────────
echo ""
echo "── Attente boot XRd (~5 min)..."
echo "   Autre terminal : docker logs router1 --follow"
echo ""
WAIT=300; STEP=10
for i in $(seq 1 $((WAIT / STEP))); do
    elapsed=$((i * STEP))
    done_b=$((elapsed * 40 / WAIT))
    todo_b=$((40 - done_b))
    bar=$(printf '%0.s#' $(seq 1 $done_b))$(printf '%0.s.' $(seq 1 $todo_b))
    printf "   [%-40s] %3ds / %ds\r" "$bar" "$elapsed" "$WAIT"
    sleep $STEP
done
echo ""

# ── STATUS ───────────────────────────────────────────────────────────────────
echo ""
echo "── Etat des containers :"
docker ps --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "========================================"
ok "DEPLOIEMENT TERMINE"
echo "========================================"
echo ""
echo "SSH :"
echo "   ssh cisco@10.10.20.101   # router1 — ingress PE / PCC"
echo "   ssh cisco@10.10.20.102   # router2 — transit P"
echo "   ssh cisco@10.10.20.103   # router3 — transit P"
echo "   ssh cisco@10.10.20.104   # router4 — egress PE / PCC"
echo "   ssh cisco@10.10.20.107   # pce     — stateful PCE"
echo "   Password: C1sco12345"
echo ""
echo "Endpoints :"
echo "   docker exec -it pc1 sh   # ping 10.3.1.2"
echo "   docker exec -it pc2 sh   # ping 10.1.1.2"
echo ""
echo "Tests rapides :"
echo "   ssh cisco@10.10.20.101 'show ospf neighbor'"
echo "   ssh cisco@10.10.20.107 'show pce peer'"
echo "   ssh cisco@10.10.20.101 'show segment-routing traffic-eng pcc ipv4 peer'"
echo "   docker exec pc1 ping -c4 10.3.1.2"
echo ""
echo "Arreter :"
echo "   docker-compose --file $TOPO_OUTPUT down --volumes"
