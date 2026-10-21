# 🏰 Lab-SRV1 — Laboratoire Cybersécurité Hyper-V

> **Lab isolé double-NAT** : SRV1 durci (Windows Server 2025) + SRV2 cible vulnérable (PME)
> Dell Latitude 5420 — 32GB RAM, i7-1185G7, Iris Xe (0 VRAM)

## Architecture

```
Internet → [NAT Routeur/RRAS] → vSwitch_Externe → SRV1 (Win Server 2025)
                                                  ↓ vSwitch_Interne
                                               SRV2 (Win Server 2025 — vulnérable)
```

- **SRV1** : DHCP, DNS, RRAS/NAT, WSUS, Windows Admin Center — durcissement complet
- **SRV2** : Simulation PME avec failles volontaires (DNS recursion, IIS, FTP anon, MariaDB root, SMB Everyone:FC)

## Structure du dépôt

```
├── 00_Fondations_Systeme/     # Optimisation hôte, roadmap réinstallation
├── 01_Architecture_Reseau/    # DOC-ARCH-001 : architecture réseau isolé Hyper-V
├── 02_Securite_Hardening/     # Documentation durcissement SRV1 + scripts
├── 03_Identite_Domaine_AD/    # DOC-DOM-001 : planification Active Directory
├── 04_Scripts_PowerShell/     # Scripts d'automatisation (maintenance, audit, sécurité)
├── 05_Audits_et_Logs/         # Scripts d'audit + logs firewall/sécurité
└── 06_Virtual_Machines/       # Documentation SRV2 (failles réseau, bilan)
```

## Artefacts prouvés

| Artefact | Fichier | Preuve |
|----------|--------|-------|
| Scripts PowerShell | `04_Scripts_PowerShell/` | 9 scripts fonctionnels (.ps1) |
| Audit forensique | `05_Audits_et_Logs/Scripts/audit_forensics.ps1` | 38KB, Sysmon intégré |
| Audit infrastructure | `05_Audits_et_Logs/Scripts/audit_infrastructure.ps1` | 45KB |
| Logs firewall | `05_Audits_et_Logs/Logs/Firewall_Rules.txt` | 50KB de règles |
| Documentation AD | `03_Identite_Domaine_AD/` | DOC-DOM-001 v1.0 → v1.1 |
| Architecture réseau | `01_Architecture_Reseau/` | DOC-ARCH-001 + v2.0/v2.1 corrigé |

## Méthodologie

- Audit avant action (transcripts horodatés)
- Snapshots Hyper-V avant chaque changement
- Masquage systématique des secrets `[MOT_DE_PASSE_MASQUE]`
- Versioning des documents (DOC-ARCH-001, DOC-DOM-001)

## Timeline

- **2026-05-24** : Premier script (AMT toggle)
- **2026-07-01** : Scripts d'audit v1→v12
- **2026-08-02** : Documentation v1.0
- **2026-08-22** : Publication GitHub

## Auteur

**Malik** — étudiant DEP Soutien Informatique, autodidacte
Spécialisation visée : Sysadmin + Cyber + AI + Cloud
