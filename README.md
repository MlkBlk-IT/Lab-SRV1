> ⚠️ **Note:** The rest of this repository (code, comments, scripts, docs, commits, issues) is written in **French**. Only this README is in English.

<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:e10600,50:1a0505,100:00ff9c&height=140&section=header&text=Lab-SRV1&fontSize=42&fontColor=e10600&fontAlignY=32&desc=Personal%20cybersecurity%20lab%20%E2%80%94%20hardened%20SRV1%20vs%20vulnerable%20SRV2%2C%20AD%2C%20Hyper-V&descAlignY=53&descSize=15&descColor=00ff9c" width="100%" alt="Lab-SRV1" />

<img src="https://img.shields.io/badge/Windows%20Server%202025-e10600?style=for-the-badge&logo=windows&logoColor=e10600&labelColor=0d0d0d" /> <img src="https://img.shields.io/badge/Hyper--V-009edc?style=for-the-badge&labelColor=0d0d0d" /> <img src="https://img.shields.io/badge/PowerShell-5391fe?style=for-the-badge&logo=powershell&logoColor=5391fe&labelColor=0d0d0d" /> <img src="https://img.shields.io/badge/Active%20Directory-00ff9c?style=for-the-badge&labelColor=0d0d0d" />

</div>

> **Isolated double-NAT lab**: hardened SRV1 (Windows Server 2025) + vulnerable target SRV2 (SMB)
> Dell Latitude 5420 — 32GB RAM, i7-1185G7, Iris Xe (0 VRAM)

## Architecture

```
Internet → [NAT Router/RRAS] → vSwitch_External → SRV1 (Win Server 2025)
                                                  ↓ vSwitch_Internal
                                               SRV2 (Win Server 2025 — vulnerable)
```

- **SRV1**: DHCP, DNS, RRAS/NAT, WSUS, Windows Admin Center — full hardening
- **SRV2**: SMB simulation with deliberate flaws (DNS recursion, IIS, anon FTP, MariaDB root, SMB Everyone:FC)

## Repository structure

```
├── 00_Fondations_Systeme/     # Host optimization, reinstall roadmap
├── 01_Architecture_Reseau/    # DOC-ARCH-001: isolated Hyper-V network architecture
├── 02_Securite_Hardening/     # SRV1 hardening documentation + scripts
├── 03_Identite_Domaine_AD/    # DOC-DOM-001: Active Directory planning
├── 04_Scripts_PowerShell/     # Automation scripts (maintenance, audit, security)
├── 05_Audits_et_Logs/         # Audit scripts + firewall/security logs
└── 06_Virtual_Machines/       # SRV2 documentation (network flaws, assessment)
```

## Proven artifacts

| Artifact | File | Proof |
|----------|------|-------|
| PowerShell scripts | `04_Scripts_PowerShell/` | 9 working scripts (.ps1) |
| Forensic audit | `05_Audits_et_Logs/Scripts/audit_forensics.ps1` | 38KB, Sysmon included |
| Infrastructure audit | `05_Audits_et_Logs/Scripts/audit_infrastructure.ps1` | 45KB |
| Firewall logs | `05_Audits_et_Logs/Logs/Firewall_Rules.txt` | 50KB of rules |
| AD documentation | `03_Identite_Domaine_AD/` | DOC-DOM-001 v1.0 → v1.1 |
| Network architecture | `01_Architecture_Reseau/` | DOC-ARCH-001 + fixed v2.0/v2.1 |

## Methodology

- Audit before action (timestamped transcripts)
- Hyper-V snapshots before every change
- Systematic secret masking `[MOT_DE_PASSE_MASQUE]`
- Document versioning (DOC-ARCH-001, DOC-DOM-001)

## Timeline

- **2026-05-24**: First script (AMT toggle)
- **2026-07-01**: Audit scripts v1→v12
- **2026-08-02**: Documentation v1.0
- **2026-08-22**: Published on GitHub

## Author

**Malik** — IT Support student (DEP), self-taught
Target specialization: Sysadmin + Cyber + AI + Cloud

---

<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:00ff9c,50:03150c,100:e10600&height=100&section=footer" width="100%" alt="" />

**⚡ Built on CPU. Proven on disk. ⚡**

</div>
