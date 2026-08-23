#!/usr/bin/env bash
# =============================================================================
# เปิด tunnel ไปยัง PostgreSQL ใน k8s สำหรับ DBeaver / psql
# =============================================================================
# Postgres เป็น ClusterIP ไม่มี External IP และ ingress ใช้ไม่ได้
# (ingress เป็น L7 สำหรับ HTTP ส่วน Postgres เป็น TCP ธรรมดา)
#
#   ./scripts/db-forward.sh          เปิด tunnel (ค้างไว้จนกด Ctrl+C)
#   ./scripts/db-forward.sh -d       เปิดแบบ background
#   ./scripts/db-forward.sh --stop   ปิด tunnel ที่เปิดค้างไว้
#   ./scripts/db-forward.sh -p 5555  ใช้พอร์ตอื่น
#
# kubectl port-forward จะตายเองเมื่อ pod restart หรือ connection หลุด
# script นี้ต่อให้ใหม่อัตโนมัติ จึงไม่ต้องคอยดูว่ายังทำงานอยู่ไหม
# =============================================================================
set -uo pipefail

NAMESPACE="${NAMESPACE:-vertex}"
SERVICE="${SERVICE:-postgres}"
LOCAL_PORT="${LOCAL_PORT:-15432}"
REMOTE_PORT="${REMOTE_PORT:-5432}"
PIDFILE="${TMPDIR:-/tmp}/vertex-db-forward.pid"
DETACH=0

while [ $# -gt 0 ]; do
    case "$1" in
        -p|--port)   LOCAL_PORT="$2"; shift 2 ;;
        -n|--namespace) NAMESPACE="$2"; shift 2 ;;
        -d|--detach) DETACH=1; shift ;;
        --stop)
            if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
                kill "$(cat "$PIDFILE")" 2>/dev/null
                rm -f "$PIDFILE"
                echo "ปิด tunnel แล้ว"
            else
                echo "ไม่มี tunnel ที่เปิดค้างอยู่"
            fi
            exit 0 ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "ไม่รู้จัก option: $1"; exit 1 ;;
    esac
done

command -v kubectl >/dev/null || { echo "🔴 ไม่พบ kubectl"; exit 1; }

if ! kubectl get svc "$SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "🔴 ไม่พบ service $SERVICE ใน namespace $NAMESPACE"
    echo "   ตรวจ kubeconfig: kubectl config current-context"
    exit 1
fi

# กันเปิดซ้อน — พอร์ตที่ถูกใช้อยู่แล้วจะทำให้ port-forward ตายทันทีแบบเงียบๆ
if lsof -nP -iTCP:"$LOCAL_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "🔴 พอร์ต $LOCAL_PORT ถูกใช้อยู่แล้ว"
    echo "   ปิดด้วย: $0 --stop   หรือใช้พอร์ตอื่น: $0 -p 15433"
    exit 1
fi

info() {
    cat <<INFO

  ✅ tunnel พร้อมใช้งาน

     Host      localhost
     Port      $LOCAL_PORT
     Database  vertex

     อ่านอย่างเดียว (แนะนำสำหรับ DBeaver)
       User      vertex_readonly
       Password  cat ~/vertex-keys/dbeaver-readonly.txt

     แก้ข้อมูลได้ (superuser)
       User      vertex_admin
       Password  kubectl get secret postgres-secret -n $NAMESPACE \\
                   -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d

     schema: pet (ข้อมูลสัตว์เลี้ยง) · auth (ผู้ใช้/สิทธิ์) · public (event)
     vertex_readonly ตั้ง search_path = pet, auth, public ไว้แล้ว
     สร้าง role นี้ใหม่ได้จาก cluster/bootstrap/000_create_readonly_role.sql

INFO
}

# วนต่อใหม่เมื่อ connection หลุด — kubectl port-forward ตายง่ายกว่าที่คิด
forward_loop() {
    while true; do
        kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE" \
            "$LOCAL_PORT:$REMOTE_PORT" >/dev/null 2>&1
        echo "  ⚠️  tunnel หลุด กำลังต่อใหม่..." >&2
        sleep 2
    done
}

if [ "$DETACH" = "1" ]; then
    forward_loop &
    echo $! > "$PIDFILE"
    sleep 3
    if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        info
        echo "  ทำงานอยู่เบื้องหลัง (pid $(cat "$PIDFILE"))  ปิดด้วย: $0 --stop"
    else
        echo "🔴 เปิด tunnel ไม่สำเร็จ"; rm -f "$PIDFILE"; exit 1
    fi
else
    trap 'echo ""; echo "  ปิด tunnel แล้ว"; exit 0' INT TERM
    info
    echo "  กด Ctrl+C เพื่อปิด"
    forward_loop
fi
