
# BILAN SRV2 — Gestion PME Québec Inc.


DOCUMENT DE RÉFÉRENCE — CIBLE RED TEAMFichier : 05.1_DOC-SRV2-001_Bilan_PME_Vuln_v1.0.docxChemin : D:\Projet Lab-SRV1\06_Virtual_Machines\SRV2\Date : 2 Août 2026Version : 1.0Auteur : Architecte Réseau & Sécurité


# 1. CONTEXTE


VM Windows Server 2022 (FR) simulant un serveur PME québécoise non-expert en sécurité.Rôle : Cible Red Team temporaire dans le lab Hyper-V. IP fixe 192.168.50.17, assignée par SRV1.Pourquoi ce scénario ? Simuler une vraie PME québécoise avec un admin non-spécialiste qui fait des erreurs classiques — réutilisation de mots de passe, services mal configurés, accès trop permissifs.


# 2. FAUSSE ENTREPRISE


Nom : Gestion PME Québec Inc.• Portail web interne IIS• Base de données de gestion employés• Partage réseau interne• Support IT : it-support@gestionpme.local | Poste 221• Admin IT fictif : Jean-Philippe


# 3. APPLICATIONS INSTALLÉES


Application

Version

Rôle

IIS

10.0

Serveur web interne

FTP (IIS)

10.0

Dépôt de fichiers

MariaDB

11.4.4 LTS

Base de données PME

SMB Share

Windows natif

Partage réseau


# 4. FAILLES VOLONTAIRES



## Couche Réseau / Firewall


• Firewall PME : RDP/SMB/WinRM/HTTP/HTTPS/SQL ouverts sans restriction IP• Aucun filtrage par plage source


## Couche Base de données


• Root MariaDB accessible à distance ([MOT_DE_PASSE_MASQUE])• 7 users avec username = password• Pas de SSL sur les connexions• Port 3306 ouvert sans restriction


## Couche SMB


• \\SRV2\Donnees — Tout le monde = Contrôle total• Aucune authentification requise


## Couche IIS / Web


• HTTP seulement, pas de HTTPS• Page d'accueil révèle : nom serveur, OS, version IIS• /admin : Basic Auth sans SSL → credentials en clair sur le réseau• /docs : Directory listing activé → fichiers leurres + web.config exposé• /uploads : Directory listing + IIS_IUSRS FullControl → webshell possible• Même mot de passe IIS et MariaDB ([MOT_DE_PASSE_MASQUE]) → réutilisation volontaire• Fichier acces_iis.txt sur le bureau avec tous les credentials en clair


## Couche Comptes


• Compte Windows local adminpme / [MOT_DE_PASSE_MASQUE]• Fichier texte credentials laissé sur le bureau (erreur sysadmin simulée)


# 5. VECTEURS D'ATTAQUE RED TEAM


• Connexion MariaDB root depuis Kali : mysql -h 192.168.50.17 -u root -p[MOT_DE_PASSE_MASQUE]• Credential stuffing via table utilisateurs sur RDP/SMB/WinRM• Sniff Basic Auth avec Wireshark sur le réseau• Upload webshell ASPX dans /uploads• Accès libre \\SRV2\Donnees• Directory traversal via /docs


# 6. SYNTHÈSE


SRV2 reproduit fidèlement les erreurs les plus courantes d'une PME sans ressources IT dédiées : mots de passe réutilisés, services exposés sans chiffrement, partages trop permissifs, et informations sensibles accessibles publiquement. Chaque faille est intentionnelle et documentée pour un usage Red Team en environnement lab isolé.
