# Lab-SRV1 — Laboratoire Cybersécurité Personnel

Portfolio professionnel — Projet d'études, DEP Soutien Informatique (EMICA)
**Auteur :** Malik Belkacemi

---

## Le projet

Un laboratoire d'entreprise complet — Active Directory, pare-feu durci, machine cible volontairement vulnérable, scénarios Red Team / Blue Team — construit entièrement sur un seul ordinateur portable (Dell Latitude 5420, i7, 32 Go RAM) via Hyper-V.

L'objectif n'était pas seulement de valider un DEP, mais de prouver une compétence réelle : concevoir, sécuriser, casser et documenter une infrastructure Windows Server, seul, avec des moyens limités, sans jamais compromettre la machine hôte.

Chaque phase suit le même principe : **audit avant action, snapshot avant tout changement risqué, documentation des écarts entre ce qui était prévu et ce qui a réellement été observé.**

## Architecture

Double NAT pour isoler complètement le lab du réseau physique de l'hôte :

```
INTERNET
   │
ROUTEUR PHYSIQUE
   │
HÔTE (Windows 11 Pro) ── ICS/SharedAccess (NAT 1) ── 192.168.137.0/24
   │
   ├── vSwitch_WAN (Internal)
   │
SRV1 (Windows Server 2025 — le cerveau)
   │  DHCP · DNS · RRAS/NAT · WAC · WSUS · pare-feu durci (7/7 tests)
   │
   ├── vSwitch_LAN (Internal) ── 192.168.50.0/24
   │
   ├── SRV2 (Windows Server 2022) — cible Red Team, PME québécoise simulée
   ├── Parrot OS — poste d'attaque
   ├── Fedora Security — SIEM prévu
   └── Win11 / Ubuntu — postes clients
```

L'hôte physique n'a **aucune** interface sur le segment LAN du lab (`vSwitch_LAN` en mode Internal). Aucune communication n'est possible entre le laptop et l'infrastructure virtuelle.

## SRV1 — le cerveau, durci

- Pare-feu Windows : politique Block Inbound par défaut sur tous les profils
- RDP, WinRM, SMB, NetBIOS fermés en entrée
- DHCP, DNS, RRAS/NAT préservés et fonctionnels
- Windows Admin Center scopé au LAN uniquement (l'installeur Microsoft l'exposait par défaut à `Any` — corrigé et documenté)
- 7 tests de validation automatisés à chaque exécution du script de durcissement, avec rollback automatique en cas d'échec

## SRV2 — la cible, volontairement vulnérable

Simule une PME québécoise administrée par un responsable IT non-spécialiste. Chaque faille est intentionnelle, documentée, et reproduit une erreur de configuration réelle et sourcée (Microsoft Learn, CIS Benchmark, Cobalt Vulnerability Wiki) — pas inventée.

| Couche | Faille |
|---|---|
| DNS | Zone transfer (AXFR) ouvert à tout serveur, récursion sans restriction, mises à jour dynamiques non sécurisées |
| HTTP / IIS | Erreurs détaillées actives à distance, en-tête personnalisé qui fuit l'IP LAN interne |
| FTP | Authentification anonyme, lecture/écriture, fichiers sensibles déposés dans le dépôt |
| MariaDB | Root accessible à distance, mots de passe = nom d'utilisateur, aucun chiffrement |
| SMB | Partage `Everyone: Full Control` |
| Comptes Windows | Mots de passe faibles et réutilisés, fichier de credentials laissé en clair sur le bureau |

La chaîne de compromission complète (reconnaissance DNS → credentials FTP → tentative d'accès administrateur) a été **validée empiriquement** depuis un poste Parrot OS séparé, en mode reconnaissance pure — sans exploit ni brute-force, conformément à la règle du projet ci-dessous.

## Règle du projet

Aucun exploit, malware, ou outil d'attaque n'est développé ou exécuté dans ce lab. L'objectif est de comprendre les mécanismes de sécurité et de reproduire des erreurs de configuration réalistes à des fins pédagogiques. Toute reconnaissance active est documentée, non-destructive, et strictement confinée à l'environnement isolé décrit ci-dessus.

## Structure du dépôt

```
00_Fondations_Systeme/     Présentation, préface, contexte du projet
01_Architecture_Reseau/    Conception réseau, journal de durcissement SRV1
02_Securite_Hardening/     Scripts et documentation du durcissement pare-feu, WAC
03_Identite_Domaine_AD/    Planification Active Directory
04_Scripts_PowerShell/     Scripts d'audit, de déploiement et de maintenance
05_Audits_et_Logs/         Logs et scripts d'audit système
06_Virtual_Machines/       Documentation par VM (SRV2 = la cible vulnérable)
```

## Note sur la confidentialité

Les mots de passe et adresses courriel présents dans les documents originaux ont été masqués (`[MOT_DE_PASSE_MASQUE]`, `[EMAIL_MASQUE]`) avant publication. Les adresses IP du lab sont conservées telles quelles : elles décrivent un réseau privé isolé (`192.168.50.0/24`, `192.168.137.0/24`) sans exposition ni signification en dehors de cet environnement.

---

*Document généré et maintenu dans le cadre du DEP Soutien Informatique — EMICA.*
