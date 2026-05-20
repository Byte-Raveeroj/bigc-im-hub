# BigC Supplier Portal IM — Knowledge Hub

Single-source-of-truth สำหรับโปรเจกต์ Item Management (NPD)

**Live URL:** (จะได้จาก Vercel หลัง deploy)

## สิ่งที่มีใน Hub

- Approval Flow + SLA per step
- Routing Rules (POG / DC / Online / RA)
- Role & Access matrix (11 roles)
- TC Dashboard (340 TCs — v2.8.2)
- Automation status (126 passing / 0 failed)
- Key Files reference
- Open Questions tracker
- Team Updates Feed (sync ทุก 09:00 น. โดย Claude Co-Work)

## Sync Workflow

1. ทีมกรอก Draft ใน Section 10 → Export JSON → วางใน `QA/updates/`
2. Claude Co-Work อ่าน JSON → embed เข้า `index.html` → push repo นี้
3. Vercel auto-deploy → URL เดิม เนื้อหาใหม่ใน ~1 นาที

## Tech Stack

Single-file HTML · React 18 + Babel (CDN) · No build step · READY MS × BigC Design System
