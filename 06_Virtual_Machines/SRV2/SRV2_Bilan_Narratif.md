05.1_BILAN_SRV2_Gestion_PME_Quebec

Bilan Technique — Serveur Applicatif Vulnérable

Document de Référence — Version 1.0Classification : Portfolio Professionnel — Confidentiel LaboratoireAuteur : Malik Belkacemi — Architecte Réseau & SécuritéDate de publication : 2 Août 2026Dépendance : DOC-ARCH-001 (v2.1) — DOC-DOM-001 (v1.1) — Phase 2 en coursChemin cible : D:\Projet Lab-SRV1\06_Virtual_Machines\SRV2\

________________________________________________________________________________


# 1. CONTEXTE


VM Windows Server 2022 (FR) simulant un serveur PME québécoise non-experte en sécurité. Cible Red Team temporaire dans le lab Hyper-V. IP fixe 192.168.50.17, assignée par SRV1.

▸ Pourquoi ce scénario ?

Simuler une vraie PME québécoise avec un admin non-spécialiste qui fait des erreurs classiques : réutilisation de mots de passe, services mal configurés, accès trop permissifs. Ce serveur est le terrain de jeu Red Team — chaque faille est intentionnelle, documentée, et isolée dans le lab.


# 2. FAUSSE ENTREPRISE


▸ Gestion PME Québec Inc.

Portail web interne IIS

Base de données de gestion employés (MariaDB)

Partage réseau interne (SMB)

Support IT : it-support@gestionpme.local | Poste 221

Admin IT fictif : Jean-Philippe

▸ Contexte narratif

Jean-Philippe est l'unique responsable IT de la PME. Il a configuré SRV2 en urgence lors d'une migration de données en décembre 2025. N'ayant pas de formation sécurité, il a laissé les configurations par défaut, réutilisé le même mot de passe partout, et documenté les accès dans un fichier texte sur le bureau 'pour ne pas les oublier'. C'est un scénario réaliste que j'ai observé dans 3 PME québécoises lors de missions d'audit.


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


Chaque faille listée ci-dessous est intentionnelle et documentée. Elle reproduit une erreur réelle observée dans des environnements de production PME.


## 4.1 Couche Réseau / Firewall


Firewall PME : RDP (3389), SMB (445), WinRM (5985/5986), HTTP (80), HTTPS (443), SQL (3306) ouverts sans restriction IP.

Aucun filtrage par plage source — tout le segment LAN 192.168.50.0/24 a accès à tous les ports.

Politique par défaut : Allow Inbound (approche 'tout ouvrir, puis restreindre si problème' — classique PME).


## 4.2 Couche Base de Données (MariaDB)


Root MariaDB accessible à distance : mysql -h 192.168.50.17 -u root -p[MOT_DE_PASSE_MASQUE]

7 utilisateurs avec username = password (ex. jpierre / jpierre, martinl / martinl).

Pas de SSL sur les connexions — credentials en transit en clair.

Port 3306 ouvert sans restriction IP.

Base 'gestionpme' contenant table 'utilisateurs' avec noms, emails, postes, et mots de passe en MD5 (pas de bcrypt).


## 4.3 Couche SMB


\\SRV2\Donnees — Tout le monde = Contrôle total (Everyone : FullControl).

Aucune authentification requise pour lister le contenu.

Partage contient : documents RH, factures PDF, et backup de la base MariaDB (.sql).


## 4.4 Couche IIS / Web


HTTP seulement, pas de HTTPS — pas de certificat TLS configuré.

Page d'accueil (Default.htm) révèle : nom serveur (SRV2), OS (Windows Server 2022), version IIS (10.0).

/admin : Basic Auth sans SSL → credentials transmis en Base64 sur le réseau (sniffable avec Wireshark).

/docs : Directory listing activé → fichiers leurres + web.config exposé (connectionStrings en clair).

/uploads : Directory listing + IIS_IUSRS FullControl → upload de webshell ASPX possible.

Même mot de passe IIS et MariaDB ([MOT_DE_PASSE_MASQUE]) → réutilisation volontaire pour démontrer l'impact.

Fichier acces_iis.txt sur le bureau avec tous les credentials en clair (erreur sysadmin simulée).


## 4.5 Couche Comptes Windows


Compte local adminpme / [MOT_DE_PASSE_MASQUE] — membre du groupe Administrateurs.

Compte local it-support / [MOT_DE_PASSE_MASQUE] — membre du groupe Opérateurs de sauvegarde.

Fichier texte 'credentials_srv2.txt' laissé sur le bureau de adminpme.

Politique de mot de passe : longueur min 6 caractères, pas de complexité imposée, jamais expirés.


# 5. VECTEURS D'ATTAQUE RED TEAM


Chaque vecteur est validable depuis Parrot OS (192.168.50.99) ou Kali.

Vecteur

Commande / Méthode

Impact

MariaDB root distant

mysql -h 192.168.50.17 -u root -p[MOT_DE_PASSE_MASQUE]

Extraction base 'gestionpme', dump credentials

Credential stuffing

Hydra / CrackMapExec sur RDP/SMB/WinRM avec table 'utilisateurs'

Compromission comptes Windows

Sniff Basic Auth

Wireshark filter : http.authbasic

Récupération credentials /admin en clair

Webshell ASPX

Upload via /uploads (PUT ou formulaire)

Exécution code à distance sur SRV2

Accès SMB libre

dir \\SRV2\Donnees

Exfiltration documents + backup base

Directory traversal

curl http://192.168.50.17/docs/

Découverte fichiers sensibles, web.config


# 6. SYNTHÈSE


SRV2 reproduit fidèlement les erreurs les plus courantes d'une PME sans ressources IT dédiées : mots de passe réutilisés, services exposés sans chiffrement, partages trop permissifs, et informations sensibles accessibles publiquement. Chaque faille est intentionnelle, documentée, et isolée dans le lab pour un usage Red Team contrôlé.

▸ Leçons retenues pour la défense (Blue Team)

Jamais de credentials en clair sur le bureau — KeePass ou gestionnaire de mots de passe d'entreprise.

Segmentation réseau : la base de données ne devrait pas être accessible depuis le segment LAN général.

HTTPS obligatoire pour toute authentification — Basic Auth sur HTTP = credentials en clair.

Principe du moindre privilège : Everyone FullControl sur SMB est une catastrophe.

Audit régulier des configurations IIS : directory listing, uploads permissifs, web.config exposé.

Politique de mot de passe robuste : 14+ caractères, complexité, expiration, historique.

▸ Prochaines étapes

Phase 5 (DOC-SRV2-001) : Déploiement technique de SRV2 avec les failles configurées.

Phase 8 (DOC-KILLCHAIN-001) : Exécution du Cyber Kill Chain depuis Parrot OS.

Documentation des logs d'attaque pour corrélation avec le SIEM (Phase 6).


# 7. GLOSSAIRE


Terme

Définition

Basic Auth

Méthode d'authentification HTTP où les credentials sont encodés en Base64 (pas chiffrés sans HTTPS).

Credential stuffing

Attaque consistant à tester des credentials volés sur plusieurs services.

Directory listing

Fonctionnalité web listant le contenu d'un répertoire — dangereuse si activée sur un dossier sensible.

Webshell

Script (ASPX, PHP, etc.) permettant l'exécution de commandes à distance via un navigateur.

MD5

Algorithme de hachage cryptographique — obsolète pour le stockage de mots de passe (cassable en secondes).

________________________________________________________________________________

Document généré le 2 Août 2026 — Version 1.0Classification : Portfolio Professionnel — Reproduction interdite sans autorisation.Auteur : Malik Belkacemi — Architecte Réseau & Virtualisation SeniorChemin cible : D:\Projet Lab-SRV1\06_Virtual_Machines\SRV2\05.1_BILAN_SRV2_Gestion_PME_Quebec_v1.0.docxFIN DU DOCUMENT
