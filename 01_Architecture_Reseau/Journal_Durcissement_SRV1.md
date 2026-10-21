JOURNAL DE BORD

Lab Cybersécurité Hyper-V

Durcissement firewall SRV1 & déploiement WSUS

Projet : DEP Soutien Informatique (EMICA) — Portfolio professionnel

Date : 12 août 2026

Machine concernée : SRV1 (Windows Server 2025 — 192.168.50.1)


# 1. Contexte et architecture


Laboratoire de cybersécurité personnel isolé, construit sur Hyper-V dans le cadre de la formation DEP Soutien Informatique (EMICA), à titre de portfolio professionnel. Approche méthodologique : audit avant action, snapshot avant tout changement risqué, capacité de rollback systématique, et documentation des écarts entre la documentation officielle et le comportement réel observé.


## 1.1 Réseau — double NAT


NAT 1 : ICS/SharedAccess de l'hôte Windows 11 → 192.168.137.0/24

NAT 2 : SRV1 via RRAS → 192.168.50.0/24 (LAN du lab)

vSwitch_WAN et vSwitch_LAN tous deux en mode Internal — hôte physique isolé du trafic du lab


## 1.2 Inventaire des machines virtuelles


VM

OS

IP

Rôle

SRV1

Windows Server 2025

192.168.50.1 (LAN) / 192.168.137.x (WAN)

DC (à venir), DHCP, DNS, RRAS, WAC — « le cerveau »

SRV2 (Winserver2022)

Windows Server 2022 FR

192.168.50.17

Cible Red Team volontairement vulnérable

FedoraSec

Fedora Security

192.168.50.15

SIEM/Monitoring prévu

Parrot

Parrot Security

192.168.50.99

Poste d'attaque

Ubuntu

Ubuntu 22.04

192.168.50.10

Serveur web/BDD prévu

Win11

Windows 11 Pro

192.168.50.12

Poste client


# 2. Durcissement du pare-feu de SRV1


Objectif : SRV1 (« le cerveau » du lab) doit être totalement inattaquable depuis les VMs du LAN, y compris depuis SRV2 en cas de compromission, tout en restant pleinement fonctionnel comme fournisseur DHCP/DNS/RRAS/WAC.


## 2.1 Constat de l'audit


Les profils de pare-feu (Domain, Private, Public) avaient déjà une politique par défaut Block Inbound, en place avant cette session. Cependant, des règles Windows natives en Allow explicite outrepassaient ce blocage par défaut : dans le modèle du pare-feu Windows, une règle Allow explicite est toujours prioritaire sur la politique DefaultInboundAction: Block, quel que soit le profil actif. Chaque service ouvert par une règle native devait donc être identifié et désactivé individuellement.


## 2.2 Règles désactivées (Disable-NetFirewallRule)


Groupe

Règle(s) désactivée(s)

Effet

RDP

RemoteDesktop-Shadow-In-TCP

RemoteDesktop-UserMode-In-TCP

RemoteDesktop-UserMode-In-UDP

Bureau à distance fermé

WinRM

WINRM-HTTP-In-TCP

WINRM-HTTP-In-TCP-PUBLIC

Gestion à distance PowerShell fermée

SMB

Microsoft-Windows-RemoteAccess-NP-In

File and Printer Sharing SMB-In Restrictive

FileServer-ServerManager-SMB-TCP-In

Partage de fichiers / admin distant fermé

IIS

World Wide Web Services — QUIC / HTTPS / HTTP Traffic-In

Serveur web fermé (non utilisé)

DCOM/WMI

Windows Management Instrumentation (DCOM-In)

File Server Remote Management (DCOM-In)

Administration distante WMI fermée

SSH

OpenSSH SSH Server (sshd)

SSH fermé (non utilisé)

Exception conservée : la règle Microsoft-Windows-DHCP-SMB-TCP-In a été laissée active — il s'agit d'une dépendance interne du rôle DHCP, non d'un vecteur d'exposition équivalent aux autres règles SMB.


## 2.3 État final du pare-feu SRV1


État

Services

Fermés

RDP, WinRM, SMB (partage/admin), IIS (HTTP/HTTPS/QUIC), DCOM/WMI distant, OpenSSH

Ouverts

WAC (scopé LAN 192.168.50.0/24 uniquement), DHCP, DNS, RRAS/NAT

La règle WAC (LAB-SRV1 WAC Inbound TCP LAN-only) est scopée au sous-réseau 192.168.50.0/24 uniquement, empêchant tout accès depuis le WAN ou l'extérieur du LAN.


## 2.4 Points restants à vérifier


Documenter formellement ces changements dans le journal de bord principal du lab (en cours avec ce document)

Vérifier isolément le port 139 (NetBIOS) — les ports 135 et 139 ont été audités conjointement lors de cette session ; seul DCOM en est ressorti comme actif


# 3. Déploiement du rôle WSUS sur SRV1


Trois rôles candidats ont été envisagés pour SRV1 : IPAM, NPS et WSUS. WSUS a été retenu comme le plus simple et le plus rapide à déployer via l'interface graphique (Add Roles and Features Wizard).


## 3.1 Étapes du wizard


#

Étape

Détail / choix retenu

1

Installation Type

Role-based or feature-based installation

2

Server Selection

SRV1 sélectionné comme serveur destination

3

Server Roles

WSUS coché ; dépendances ajoutées automatiquement (IIS, .NET Framework 4.8, WID, outils RSAT)

4

Features

Aucune fonctionnalité additionnelle cochée

5

Role Services

WID Connectivity + WSUS Services cochés (Windows Internal Database — pas de SQL Server séparé, suffisant pour un lab)

6

Content location

Stockage local des mises à jour : C:\WSUS

7

Confirmation

Avertissement de redémarrage en attente (KB .NET Framework, sans lien avec WSUS) — installation lancée malgré tout

8

Installation

En cours au moment de la rédaction : configuration IIS puis WSUS Services / WID Connectivity


## 3.2 Détails techniques du choix


Base de données : Windows Internal Database (WID) — pas de serveur SQL Server dédié, choix adapté à un environnement de lab

Stockage des mises à jour : C:\WSUS (chemin local sur SRV1)

Composants installés automatiquement en dépendance : IIS (rôle Web Server), .NET Framework 4.8 (ASP.NET 4.8, WCF Services, HTTP Activation), Windows Process Activation Service, outils d'administration RSAT (WSUS Tools, cmdlets PowerShell, console de gestion)


## 3.3 État au moment de la rédaction


L'installation est en cours d'exécution (configuration d'IIS puis des services WSUS/WID). Un redémarrage était déjà en attente avant le lancement de cette installation (KB5120708 — mise à jour de sécurité .NET Framework), sans lien avec le déploiement WSUS ; il devra être traité une fois l'installation terminée.


## 3.4 Étapes suivantes (à réaliser)


Fin de l'installation → fermeture du wizard (Close)

Exécution des Post-Installation tasks WSUS (obligatoire, lancée depuis Server Manager avant toute utilisation)

Configuration initiale : sélection des produits et classifications à synchroniser, langues, planification de synchronisation

Traitement du redémarrage en attente


# 4. Suite installation WSUS — post-déploiement


Après la fin du wizard (Installation succeeded on Srv1), les Post-Installation tasks se sont lancées automatiquement depuis Server Manager. Le rôle WSUS est apparu dans le menu de navigation et dans la liste des rôles (Roles: 6).

Post-deployment Configuration : statut passé de « Running » à « Configuration completed for Windows Server Update Services at SRV1 »

Deux entrées dans les Events au moment du post-deployment : ID 13051 (Warning) et ID 13042 (Error), source Windows Server Update Services, horodatées 3:19:57 AM — à investiguer avant la configuration initiale (produits/classifications)

Un redémarrage était déjà en attente avant l'installation WSUS (KB5120708 .NET Framework) ; une seconde mise à jour (KB5120233) était en cours d'installation au même moment — le redémarrage a été volontairement reporté pour ne pas interrompre cette installation

Configuration initiale de WSUS (Getting Started Wizard : produits, classifications, langues, planification de synchronisation) non encore réalisée — en attente de la fin des mises à jour Windows et du redémarrage de SRV1.


# 5. Décision — rôle supplémentaire pour SRV1


Rôles envisagés en complément (NPS, IPAM, AD CS, FSRM, Windows Server Backup) pour renforcer SRV1 sans dépendre d'Active Directory. Windows Server Backup retenu comme candidat le plus pertinent : installation rapide en GUI, aucune dépendance lourde, et répond à un besoin concret — pouvoir restaurer SRV1 rapidement s'il est affecté pendant les tests Red Team menés depuis Parrot/SRV2.

Décision finale et installation non encore réalisées à la coupure de cette session


# 6. Règle du projet


Aucun exploit, malware ou modèle IA orienté offensive security pure (ex. WhiteRabbitNeo, modèles « abliterated » pour le hacking) n'est développé ou assisté dans le cadre de ce projet. L'objectif est de comprendre les mécanismes de sécurité et de durcir/configurer les systèmes, non de générer des outils d'attaque.
