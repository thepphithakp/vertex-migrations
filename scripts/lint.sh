#!/usr/bin/env bash
# ตรวจกฎที่เคยทำให้พลาดมาแล้วจริง
set -uo pipefail
fail=0

echo "--- ชื่อไฟล์ถูกรูปแบบ ---"
for f in */migration/V*.sql; do
  [[ $(basename "$f") =~ ^V[0-9]+__[a-z0-9_]+\.sql$ ]] || { echo "  ❌ $f — ต้องเป็น V<เลข>__snake_case.sql"; fail=1; }
done
for f in */codeowned/R__*.sql */seed/R__*.sql; do
  [ -e "$f" ] || continue
  # R__ รันตามลำดับตัวอักษรของ description จึงต้องมีเลข 4 หลักนำหน้าเสมอ
  [[ $(basename "$f") =~ ^R__[0-9]{4}_[a-z0-9_]+\.sql$ ]] || { echo "  ❌ $f — ต้องเป็น R__NNNN_snake_case.sql"; fail=1; }
done

echo "--- ไม่มีเลข version ซ้ำในแต่ละ service ---"
for svc in pet auth; do
  dup=$(ls $svc/migration/V*.sql 2>/dev/null | sed -E 's|.*/V([0-9]+)__.*|\1|' | sort | uniq -d)
  [ -n "$dup" ] && { echo "  ❌ $svc มี version ซ้ำ: $dup"; fail=1; }
done

echo "--- ไม่มี CHECK constraint กับค่าที่มาจาก master data ---"
# master data แก้ผ่าน backoffice ได้ CHECK จะทำให้ค่าใหม่ใช้ไม่ได้
# ตัดบรรทัดคอมเมนต์ออกก่อน — grep -rn ใส่ "ไฟล์:บรรทัด:" นำหน้า
# จึงต้องเทียบ -- ที่ตำแหน่งหลัง prefix ไม่ใช่ต้นบรรทัด
if grep -rniE "CHECK *\(.*(type|gender|species|breed|blood_type) +IN +\(" */migration/*.sql 2>/dev/null \
   | grep -vE "^[^:]+:[0-9]+: *--"; then
  echo "  ❌ เจอ CHECK constraint กับค่าที่แก้ผ่าน UI ได้ — ใช้ FOREIGN KEY NOT VALID แทน"
  fail=1
fi

echo "--- ไม่มีการเปิด flyway clean ---"
grep -rn "cleanDisabled *= *false\|CLEAN_DISABLED.*false" . 2>/dev/null | grep -v lint.sh && { echo "  ❌ ห้ามเปิด clean"; fail=1; }

[ $fail -eq 0 ] && echo "✅ ผ่านทั้งหมด" || echo "🔴 มีข้อผิดพลาด"
exit $fail
