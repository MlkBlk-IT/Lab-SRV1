PROJET LAB-SRV1

PORTFOLIO CYBERSÉCURITÉ

Officialisation de

Windows Admin Center (WAC) sur SRV1

Référence document : 05.2_DOC-WAC-001

Version 1.0

Date de publication : 2026-08-10

Travaux exécutés le : 2026-08-09

Auteur : Malik Belkacemi

Projet personnel de formation — DEP Soutien Informatique (EMICA)

Classification : Portfolio professionnel — Lab de cybersécurité personnel


# Table des matières



# 1. Résumé exécutif


Windows Admin Center (v2) 2.4.1.2 a été installé sur SRV1 le 2026-08-09, mais n'avait jamais été documenté ni aligné sur les règles de sécurité du lab. Ce document officialise le service : inventaire complet, correction du scope firewall (la règle créée par l'installeur exposait le port 443 à n'importe quelle source), validation par 4 tests conformes, et procédure de rollback.

Conclusion : WAC est opérationnel, scopé LAN (192.168.50.0/24) uniquement, non exposé au host ni au WAN, conformément à la règle d'or du projet (« aucun service exposé au host »).


# 2. Contexte pédagogique — Qu'est-ce que Windows Admin Center ?


Windows Admin Center est l'outil moderne de Microsoft qui remplace la galaxie MMC / RSAT / Server Manager par un portail web unique (single pane of glass). Architecture observée et documentée :

Gateway HTTPS sur TCP 443, servi par le processus WindowsAdminCenter (ASP.NET Core auto-hébergé sur Kestrel — PAS HTTP.sys, contrairement à IIS ou WinRM).

Administration des machines distantes via WinRM / PowerShell Remoting.

Authentification contre le backend Windows présent sur la machine : SAM local en WORKGROUP (notre cas, AD DS non installé), Kerberos en environnement domaine (Phase 2).

Couverture fonctionnelle : services, événements, performance, firewall, DHCP, DNS, certificats, disques, Hyper-V (VMs, checkpoints), sessions PowerShell à distance, extensions (Azure, etc.).


## Pourquoi WAC dans mon lab


SRV1 est le cerveau du lab (DHCP, DNS, RRAS, IIS, futur WSUS, futur AD DS) : WAC donne un tableau de bord centralisé.

Gestion des VMs LAN (dont SRV2, cible Red Team) sans multiplier les RDP.

Compatible WORKGROUP : utilisable dès la Phase 1, avant l'AD DS.

Intérêt cybersécurité : service web exposé sur 443 = excellente étude de cas sur l'importance du scoping firewall et du durcissement.


# 3. État initial constaté (audit du 2026-08-09/10)


Installation GUI complétée 20:01, case « Start Windows Admin Center : https://Srv1:443 » cochée → ouverture automatique du navigateur.

Service WindowsAdminCenter : StartType Automatic (observé Stopped lors de l'audit, démarré à l'étape 3). Service secondaire WindowsAdminCenterAccountManagement : Manual, Stopped, non touché.

Constat critique : l'installeur a créé la règle firewall « WacInboundOpenException » = Allow TCP 443 depuis TOUTE source (Any). Violation directe de la règle d'or du lab.

netsh http show iplisten : vide. netsh http show sslcert : vide → cohérent avec WAC v2 (Kestrel), le TLS et le certificat self-signed sont servis in-process.

Annotation personnelle #1 : « Mon premier réflexe a été de paniquer devant la page Sign in : je croyais que WAC avait créé un compte inconnu. whoami a réglé ça en 2 secondes : srv1\administrator. Leçon : WAC ne crée JAMAIS de compte ; il s'appuie sur le backend Windows local. Toujours identifier le backend d'authentification avant de conclure à un problème. »


# 4. Travail effectué — déroulé étape par étape


ÉTAPE 1 — Audit read-only (zéro modification)

Registre (version, chemin), services, listeners TCP, état HTTP.sys, règles firewall existantes.

Explication : en environnement durci, on n'écrit jamais avant d'avoir lu. L'audit a révélé le port réel (443), le listener, et la règle ouverte à neutraliser.

ÉTAPE 2 — Scoping firewall LAN-only (modification réversible)

a) Création de LAB-SRV1-WAC-In-TCP-LAN : Inbound / Allow / TCP 443 / RemoteAddress 192.168.50.0/24 / InterfaceAlias = NIC LAN / tous profils.

b) Désactivation de WacInboundOpenException.

Explication : WAC écoute sur toutes les interfaces ([::]:443). Le firewall est donc la SEULE barrière de scope. L'ordre compte : on verrouille AVANT de démarrer le service, jamais l'inverse.

Annotation personnelle #2 : « Je ne fais jamais confiance aux défauts d'un installeur. Ici, le défaut Microsoft (443 ouvert à Any) est acceptable en entreprise joinée domaine avec firewall périmétrique, mais inacceptable dans mon lab où le host doit rester isolé. Leçon : auditer les règles créées par chaque installation. »

ÉTAPE 3 — Démarrage du service et validation du listener

Start-Service → Running. Listener confirmé : [::]:443, PID du processus WindowsAdminCenter.

Explication : sslcert vide n'est PAS une anomalie pour WAC v2 (Kestrel ≠ HTTP.sys). Ne pas plaquer les réflexes de diagnostic IIS sur WAC.

ÉTAPE 4 — Authentification

Sign-in avec .\Administrator (SAM local, WORKGROUP). Dashboard srv1 affiché (Overview : WORKGROUP, Server 2025 Standard, 2 NICs).

ÉTAPE 5 — Batterie de tests (4/4 conformes)

Test

Description

Résultat

Statut

T1

SRV1 → https://Srv1:443

Sign-in + dashboard

✓

T2

SRV1 → 192.168.50.1:443

True → binding IP LAN confirmé

✓

T3

HOST → 192.168.50.1:443

False → host sans route vers LAN

✓

T4

HOST → 192.168.137.2:443 (WAN)

False → preuve forte (listener actif, seul le firewall bloque)

✓

Annotation personnelle #3 : « T3 seul ne prouvait rien : l'échec venait de l'absence de route, pas du firewall. C'est T4 (IP WAN, route existante, listener actif) qui constitue la vraie preuve. Leçon de méthodologie : un test négatif doit éliminer les causes alternatives avant de conclure. »


# 5. Synthèse professionnelle


L'officialisation de WAC a transformé un service installé « en cachette » en composant inventorié, sécurisé et testé. La valeur ajoutée n'est pas l'installation elle-même, mais la démarche : audit read-only, verrouillage avant démarrage, tests positifs ET négatifs, documentation réversible. WAC devient l'outil d'administration quotidien de SRV1 et une pièce du portfolio démontrant la maîtrise du durcissement d'un service web Windows en environnement segmenté (double NAT ICS + RRAS).


## Fiche technique validée


Service

Windows Admin Center (v2) 2.4.1.2 — C:\Program Files\WindowsAdminCenter\

Listener

[::]:443 (Kestrel, TLS in-process, certificat self-signed)

URLs

https://Srv1:443  |  https://192.168.50.1

Authentification

SAM local — .\Administrator (WORKGROUP)

Règle allow

LAB-SRV1-WAC-In-TCP-LAN (443, 192.168.50.0/24, NIC LAN)

Règle neutralisée

WacInboundOpenException = Disabled

Tests

4/4 conformes — aucune exposition host/WAN


# 6. Limites connues et suivi


Certificat self-signed (avertissement name-mismatch) : acceptable Phase 1, à remplacer par un certificat CA interne post-AD DS (Phase 2).

Auth locale : à migrer vers Kerberos domaine en Phase 2.

Test positif depuis VM LAN (VM Win11 + DHCP 192.168.50.0/24) : pending, non bloquant.

IIS : aucun binding HTTPS actif à ce jour ; vigilance requise à son officialisation (conflit possible sur 443).

Prochain service candidat : WSUS.


# 7. Rollback (réversible)


Procédure de retour à l'état antérieur, à exécuter dans l'ordre indiqué :

Stop-Service -Name 'WindowsAdminCenter'

Enable-NetFirewallRule -DisplayName 'WacInboundOpenException'

Remove-NetFirewallRule -Name 'LAB-SRV1-WAC-In-TCP-LAN'


# 8. Glossaire technique


Termes et acronymes techniques utilisés dans ce document, définis pour assurer la lisibilité du portfolio par un lecteur non spécialiste.

Terme

Définition

WAC

Windows Admin Center — portail web unique de Microsoft pour l'administration de serveurs Windows, remplaçant MMC/RSAT/Server Manager.

Kestrel

Serveur web léger et multiplateforme intégré à ASP.NET Core, utilisé en interne par WAC v2 pour servir le HTTPS sans dépendre de HTTP.sys.

HTTP.sys

Pilote noyau Windows qui gère normalement l'écoute HTTP/HTTPS pour IIS et WinRM ; WAC v2 ne l'utilise pas.

WinRM

Windows Remote Management — protocole standard de gestion à distance de Windows, basé sur WS-Management, utilisé par WAC pour piloter les hôtes distants.

SAM

Security Account Manager — base de comptes locaux d'une machine Windows, utilisée en l'absence d'un contrôleur de domaine (mode WORKGROUP).

Kerberos

Protocole d'authentification réseau utilisé en environnement Active Directory (domaine), prévu pour la Phase 2 du lab.

Scope firewall

Restriction des adresses sources autorisées à atteindre un port ou service, ici limitée au sous-réseau LAN 192.168.50.0/24.

Listener

Processus ou service qui écoute activement les connexions entrantes sur une adresse et un port réseau donnés.

Double NAT (ICS + RRAS)

Architecture réseau du lab combinant le partage de connexion Windows (ICS) et le service de routage RRAS pour isoler le LAN du WAN/host.

Read-only (audit)

Principe méthodologique consistant à observer et documenter l'état d'un système avant toute modification.


# 9. Références croisées


Documents du projet Lab-SRV1 liés à cette officialisation :

Document

Lien avec ce document

05.1_DOC-SRV2-001

Documentation de SRV2, machine cible désignée pour les exercices Red Team du lab.

01.x_Architecture_Reseau

Schéma et validation de l'architecture réseau double NAT (ICS + RRAS), validée le 09/08/2026.

03.x_Identite_Domaine_AD

Plan de mise en place d'Active Directory — Phase 2, prérequis PRQ-02 et PRQ-04.

Firewall durci v3

Rapport de durcissement du pare-feu du lab (7/7 tests conformes).


# 10. Historique des révisions


Version

Date

Description

Auteur

1.0

2026-08-10

Officialisation initiale du service WAC sur SRV1

M. Belkacemi


# Annexes



## Annexe A — Captures d'écran


Références des captures documentant le déroulement chronologique de l'installation et de la validation. Les images sont à insérer aux emplacements indiqués lors de la finalisation du portfolio.

Réf.

Capture

Heure

Contenu

A1

Installeur en cours d'exécution

19:38

Fenêtre d'installation WAC affichant la progression du setup.

A2

Fin d'installation + URL 443

20:01

Écran de fin d'install avec case cochée et URL https://Srv1:443.

A3

Page Sign in

20:09

Formulaire d'authentification WAC avant saisie des identifiants SAM.

A4

Dashboard Overview

20:16

Tableau de bord principal : WORKGROUP, Server 2025 Standard, 2 NICs.

A5

Outputs PowerShell

—

Sorties console de l'audit, création/désactivation des règles firewall, et résultats des tests T2 à T4.


## Annexe B — Commandes PowerShell de référence


Commandes clés utilisées lors de l'audit et de la configuration (voir section 4 pour le contexte complet) :

Get-Service WindowsAdminCenter, WindowsAdminCenterAccountManagement

Get-NetFirewallRule -DisplayName '*Wac*' | Select DisplayName, Enabled, Direction, Action

netsh http show iplisten

netsh http show sslcert

New-NetFirewallRule -DisplayName 'LAB-SRV1-WAC-In-TCP-LAN' -Direction Inbound -Protocol TCP -LocalPort 443 -RemoteAddress 192.168.50.0/24 -Action Allow

Disable-NetFirewallRule -DisplayName 'WacInboundOpenException'

Start-Service -Name 'WindowsAdminCenter'

Test-NetConnection -ComputerName 192.168.50.1 -Port 443
