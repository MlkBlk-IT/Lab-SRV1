05.3_DOC-SRV2-002_Addendum_Failles_Reseau_v1.0

PROJET LAB-SRV1

PORTFOLIO CYBERSÉCURITÉ

Addendum — Failles Réseau et Services Additionnelles

SRV2 — Gestion PME Québec Inc.

Référence document : 05.3_DOC-SRV2-002

Version 1.1

Date de publication : 20 août 2026

Travaux exécutés le : 17 août 2026 (configuration) — 20 août 2026 (validation recon depuis Parrot)

Auteur : Malik Belkacemi

Projet personnel de formation — DEP Soutien Informatique (EMICA)

Classification : Portfolio professionnel — Lab de cybersécurité personnel

Dépendance : 05.1_DOC-SRV2-001_Bilan_PME_Vuln_v1.0

Chemin cible : D:\Projet Lab-SRV1\06_Virtual_Machines\SRV2\


# 1. Résumé exécutif


Ce document complète le bilan technique 05.1_DOC-SRV2-001 en documentant quatre nouvelles failles volontaires ajoutées sur SRV2 (192.168.50.17) le 17 août 2026 : une configuration DNS non sécurisée (rôle DNS ajouté à SRV2), un mécanisme de fuite d'adresse IP interne via HTTP, un service FTP anonyme en lecture/écriture, et la confirmation d'un vecteur de compromission totale via WinRM combiné à la réutilisation de mots de passe déjà documentée.

Chaque faille a été introduite manuellement via l'interface graphique de Windows Server 2022, en suivant la même démarche méthodologique que le reste du projet : recherche des erreurs de configuration réelles et documentées (sources Microsoft Learn, CIS Benchmark, Cobalt Vulnerability Wiki), puis reproduction fidèle en environnement isolé.

Conclusion : SRV2 dispose désormais d'un chemin de compromission complet et cohérent, de la reconnaissance DNS jusqu'à l'exécution de commandes avec droits administrateur à distance, sans qu'aucune de ces failles n'affecte SRV1 (cerveau du lab, non touché par cet addendum).


# 2. Contexte méthodologique


SRV2 simule un serveur PME québécoise administré par un responsable IT non-spécialiste (« Jean-Philippe », cf. 05.1_DOC-SRV2-001). Les failles ajoutées dans cet addendum suivent la même logique narrative : des choix de configuration rapides, faits pour « que ça marche », sans évaluation de l'impact sécurité — recherchés au préalable comme des erreurs réellement documentées dans des audits et guides de durcissement professionnels, plutôt qu'inventées.

Aucune de ces modifications ne touche SRV1. SRV2 reste isolé et dépend de SRV1 uniquement pour son accès Internet (NAT via RRAS).


# 3. Rôle ajouté — DNS (Windows Server)


Le rôle DNS a été installé sur SRV2 le 17 août 2026 via Gestionnaire de serveur (Add Roles and Features Wizard), puis configuré de façon volontairement non sécurisée via le Gestionnaire DNS (dnsmgmt.msc).


## 3.1 Étapes de configuration


Création d'une zone principale standalone pme.local (non intégrée à Active Directory — SRV2 est en WORKGROUP), fichier de zone par défaut.

Mises à jour dynamiques configurées sur « Non sécurisé et sécurisé » (Nonsecure and secure) — accepte les mises à jour dynamiques non authentifiées.

Transfert de zone (Zone Transfer / AXFR) autorisé « Vers n'importe quel serveur » (To any server), au lieu d'être restreint aux serveurs listés.

Récursion DNS active par défaut au niveau serveur (case « Désactiver la récursivité » non cochée), sans restriction de scope réseau.


## 3.2 Failles DNS documentées


#

Faille

Mécanisme exploité

Impact Red Team

1

Zone Transfer (AXFR) non restreint

Allow Zone Transfers = To any server

dig axfr @192.168.50.17 pme.local exfiltre l'intégralité de la zone : noms de machines, sous-domaines internes — cartographie réseau gratuite

2

Récursion ouverte sans restriction

Recursion active, allow-query non scopé au LAN

Cache poisoning, base pour attaque d'amplification DNS si le service était exposé au-delà du LAN

3

Mises à jour dynamiques non sécurisées

AllowUpdate = Nonsecure and secure

N'importe quelle machine du LAN peut injecter ou modifier un enregistrement A (ex. usurper srv1.pme.local)

4

Pas de DNSSEC

Aucune signature de zone

Aucune vérification d'authenticité des réponses DNS — spoofing de réponse facilité

Sources : Cobalt Vulnerability Wiki (Misconfigured DNS — Zone Transfer), CIS BIND Benchmark section 4.2 (Restricting recursive queries), Microsoft Learn (risques des mises à jour dynamiques non sécurisées).


# 4. Fuite d'adresse IP interne via HTTP (IIS)


SRV2 étant isolé derrière SRV1 (double NAT ICS + RRAS), toute fuite de l'adresse IP LAN réelle (192.168.50.17) depuis une réponse HTTP constitue une faille de reconnaissance directe pour un attaquant externe au segment ou un outil d'énumération automatisé.


## 4.1 Configuration appliquée


Pages d'erreurs IIS basculées sur « Erreurs détaillées » (Detailed Errors) pour les demandes locales ET distantes, au niveau du site Default Web Site — expose les chemins physiques du serveur (C:\inetpub\wwwroot\...) et la stack technique en cas d'erreur applicative.

En-tête de réponse HTTP personnalisé ajouté au niveau du site : X-Backend-Server = 192.168.50.17, envoyé sur chaque réponse HTTP, y compris pour les requêtes valides.


## 4.2 Vérification


Un attaquant peut confirmer la fuite avec une simple requête :

curl -I http://192.168.50.17

L'en-tête X-Backend-Server apparaît directement dans la réponse, révélant l'adresse IP interne réelle du serveur sans authentification préalable.

Ce type d'erreur correspond à un en-tête de debug/proxy oublié en production ou à une mauvaise configuration de reverse-proxy — un des cas classiques de divulgation d'information via en-têtes HTTP.


# 5. Service FTP — Authentification anonyme (IIS FTP)


Un site FTP dédié a été créé sur SRV2 via IIS Manager, distinct du site web principal.


## 5.1 Configuration appliquée


Paramètre

Valeur

Nom du site FTP

Depot-PME

Chemin d'accès physique

C:\Depot-FTP

Liaison

Toutes IP non attribuées, port 21

SSL

Pas de SSL (aucun chiffrement du canal ni des identifiants)

Authentification anonyme

Activée

Authentification de base

Désactivée

Autorisation

Tous les utilisateurs — Lecture + Écriture


## 5.2 Contenu déposé (erreur sysadmin simulée)


Après mise en service, deux fichiers ont été déposés dans C:\Depot-FTP par le personnage de Jean-Philippe, reproduisant l'usage détourné classique d'un dépôt FTP « de dépannage » comme espace de stockage temporaire de documents sensibles :

acces_iis — reprend les identifiants IIS/MariaDB déjà documentés en clair (cf. 05.1_DOC-SRV2-001, section 4.4).

SRV2_MariaDB_Rapport — rapport technique interne sur la base de données de gestion PME.


## 5.3 Impact Red Team


Connexion anonyme sans identifiants requis (ftp 192.168.50.17, utilisateur anonymous), énumération et téléchargement libres du contenu du dépôt, upload de fichiers arbitraires possible (écriture autorisée). L'accès anonyme expose directement des identifiants applicatifs et un document interne, sans qu'aucune étape d'authentification ou d'exploitation ne soit nécessaire.


# 6. Vecteur de compromission totale — WinRM


Contrairement aux failles précédentes, ce point ne résulte pas d'une modification volontaire mais de la confirmation d'un état par défaut de Windows Server, combiné aux comptes et mots de passe déjà documentés dans le bilan initial (05.1_DOC-SRV2-001).


## 6.1 Constat d'audit


Élément vérifié

Commande

Résultat

Service WinRM

Get-Service WinRM

Running

PSRemoting

Enable-PSRemoting -Force

« WinRM est déjà configuré pour recevoir des demandes sur cet ordinateur »

Comptes locaux administrateurs à distance

(sortie de Enable-PSRemoting)

LocalAccountTokenFilterPolicy configuré — les comptes admin locaux (WORKGROUP) obtiennent les pleins droits d'administration à distance via WinRM

Règle firewall

Get-NetFirewallRule -DisplayGroup "Gestion à distance de Windows"

Gestion à distance de Windows (HTTP-Entrée) — Enabled: True — Profils Domain, Private, Public — aucune restriction d'adresse source


## 6.2 Chaîne de compromission complète


WinRM est activé par défaut sur Windows Server et, sur profil réseau privé/domaine, le pare-feu autorise déjà toutes les connexions entrantes vers le port 5985 (HTTP). SRV2 étant en WORKGROUP, LocalAccountTokenFilterPolicy permet à tout compte membre du groupe Administrateurs local de s'authentifier avec ses pleins droits via WinRM — sans restriction supplémentaire propre au workgroup.

Correction v1.1 (validée par recon Parrot le 20 août 2026) : adminpme n'est PAS membre du groupe Administrateurs local (Appartient aux groupes locaux : *Aucun, confirmé via net user adminpme sur SRV2). Il s'agit d'une erreur d'administration simulée volontaire — le compte a été créé et son mot de passe partagé avec les autres services (IIS, MariaDB), mais jamais réellement ajouté au groupe Administrateurs. Seul le compte intégré Administrateur figure dans ce groupe. La chaîne d'attaque ci-dessous est donc théorique avec adminpme : WinRM refuse l'authentification (WinRMAuthorizationError) malgré des identifiants valides en SMB et IIS. Voir section 12 pour le détail de la validation.

La chaîne d'attaque théorique, telle que documentée initialement, s'appuyant sur les failles déjà en place dans le lab :

1. Reconnaissance DNS : dig axfr @192.168.50.17 pme.local révèle la structure du réseau interne.

2. Découverte de credentials : accès FTP anonyme (section 5) → lecture de acces_iis ([MOT_DE_PASSE_MASQUE]) ou du fichier credentials_srv2.txt laissé sur le bureau (cf. 05.1_DOC-SRV2-001).

3. Accès administrateur à distance (théorique) : Enter-PSSession -ComputerName 192.168.50.17 -Credential adminpme — ÉCHEC réel confirmé, adminpme n'a pas les droits admin (voir section 12).

4. Compromission totale : nécessite soit le mot de passe du compte Administrateur natif (non documenté, non exposé dans les fichiers accessibles), soit une élévation de privilège locale distincte depuis un accès SMB/IIS déjà obtenu.

Point clé : WinRM offre un accès shell complet et scriptable, contrairement à RDP (interactif) ou SMB (fichiers seuls) — mais seulement pour un compte réellement privilégié. La faille de reconnaissance et de fuite de credentials reste réelle et exploitable pour l'accès fichiers/web/DB ; l'étape finale vers un shell admin complet nécessite un maillon supplémentaire non encore identifié dans le lab.


# 12. Validation par reconnaissance externe (Parrot OS) — 20 août 2026


Une session de reconnaissance a été menée depuis Parrot OS (192.168.50.99) contre SRV2, en mode recon-only : aucun exploit, aucun brute-force, aucune écriture sur SRV2, aucune exfiltration vers le disque de Parrot. Objectif : valider empiriquement les failles décrites dans les sections précédentes.


## 12.1 Conditions du test


SRV1 volontairement éteint (test d'isolation L2) — DHCP/DNS absents, IP statique attribuée manuellement sur Parrot et SRV2.

vSwitch_LAN confirmé en mode Private (non Internal) — hôte physique sans interface sur ce segment.


## 12.2 Résultats


Test

Méthode

Résultat

Isolation L2 intra-LAN

ping Parrot ↔ SRV2

0% perte — confirme que SRV1 ne gère pas le forwarding L2 (DHCP/DNS/NAT uniquement)

Scan de ports

nmap -sV -p- -Pn -n

17 ports ouverts confirmés : FTP 21, DNS 53, HTTP 80, RPC 135, NetBIOS 139, SMB 445, MariaDB 3306, RDP 3389, WinRM 5985/47001

Rôle DNS

Get-Service, Get-DnsServerZone sur SRV2

Zone pme.local confirmée Primary, IsDsIntegrated=False, conforme section 3

Défense périmétrique

Get-MpComputerStatus / Get-MpThreatDetection

Defender actif mais aucune détection du scan — signature-based uniquement, aveugle à la reconnaissance réseau

Fuite IP HTTP

curl -I http://192.168.50.17

En-tête X-Backend-Server: 192.168.50.17 confirmé, conforme section 4

FTP anonyme

curl ftp://192.168.50.17

Login anonymous accepté, listing et lecture de acces_iis.txt et SRV2_MariaDB_Rapport.txt réussis

Contenu des fichiers FTP

Lecture stdout des deux fichiers

Creds IIS/MariaDB confirmés, 7 comptes applicatifs listés, ALLOWREMOTEROOTACCESS=1 documenté par l'admin fictif lui-même

Énumération SMB anonyme

smbclient -N

Refusée (ACCESS_DENIED) — le partage Everyone n'accorde pas de session anonyme, une authentification (même faible) reste requise

Énumération SMB authentifiée

smbclient -U adminpme

Réussie — partages ADMIN$, C$, Donnees, IPC$ listés ; Donnees trouvé vide (écart avec la description narrative du bilan initial)

Accès WinRM avec adminpme

evil-winrm -u adminpme

ÉCHEC — WinRMAuthorizationError, malgré mot de passe valide (confirmé par SMB)


## 12.3 Écarts identifiés entre la documentation et l'état système réel


Dossier \\SRV2\Donnees vide au moment du test, alors que la documentation narrative (05.1_DOC-SRV2-001) le décrit contenant documents RH, factures et backup MariaDB — ces fichiers n'ont jamais été effectivement déposés, ou ont été retirés.

adminpme accède à ADMIN$ et C$ en plus du partage Donnees prévu — accès au disque système complet via SMB, non explicitement documenté dans le bilan initial.

adminpme n'est membre d'aucun groupe local (ni Administrateurs, ni Utilisateurs explicite) — la chaîne de compromission WinRM section 6.2 ne fonctionne pas telle quelle avec ce compte.


## 12.4 Vecteur théorique non testé — brute-force


Puisque adminpme ne mène pas à un shell administrateur, le prochain maillon logique pour un attaquant réel serait de cibler directement le compte intégré Administrateur (RDP, WinRM ou SMB) par credential stuffing ou brute-force, en s'appuyant sur les mots de passe déjà collectés ([MOT_DE_PASSE_MASQUE], ou les 7 combos username=password de la table utilisateurs). Aucune politique de verrouillage de compte (account lockout policy) n'a été vérifiée sur SRV2 à ce jour — un point à auditer.

Ce vecteur n'a volontairement PAS été exécuté, conformément à la règle du projet (aucun exploit ni brute-force développé ou assisté). Il est documenté ici uniquement comme prochaine étape théorique de la kill chain, au même titre que les vecteurs listés dans 05.1_DOC-SRV2-001 section 5.


# 7. Synthèse — Vue d'ensemble des failles SRV2


Récapitulatif complet, incluant les failles du bilan initial (05.1_DOC-SRV2-001) et celles ajoutées dans cet addendum, organisées par couche.


## 7.1 Couche Réseau / Firewall


RDP (3389), SMB (445), WinRM (5985/5986), HTTP (80), HTTPS (443), SQL (3306) ouverts sans restriction IP source.

Politique par défaut : Allow Inbound sur tout le segment LAN 192.168.50.0/24.


## 7.2 Couche DNS (ajout addendum)


Zone pme.local standalone, mises à jour dynamiques non sécurisées.

Transfert de zone ouvert à n'importe quel serveur (AXFR).

Récursion active sans restriction de scope.


## 7.3 Couche HTTP / IIS


HTTP seulement, pas de HTTPS.

Erreurs détaillées actives en local ET à distance (ajout addendum).

En-tête X-Backend-Server exposant l'IP LAN 192.168.50.17 (ajout addendum).

/admin : Basic Auth sans SSL — credentials en Base64 sniffable.

/docs et /uploads : Directory listing, web.config exposé, upload webshell ASPX possible.

Même mot de passe IIS/MariaDB ([MOT_DE_PASSE_MASQUE]) — réutilisation volontaire.


## 7.4 Couche FTP (ajout addendum)


Site Depot-PME : authentification anonyme activée, Lecture + Écriture, pas de SSL.

Fichiers sensibles déposés dans le dépôt (identifiants, rapport MariaDB).


## 7.5 Couche Base de données (MariaDB)


Root MariaDB accessible à distance ([MOT_DE_PASSE_MASQUE]), port 3306 sans restriction.

7 utilisateurs avec username = password. Pas de SSL. Mots de passe en MD5.


## 7.6 Couche SMB


\\SRV2\Donnees — Everyone Full Control, aucune authentification requise.


## 7.7 Couche Comptes Windows / WinRM (confirmation addendum)


Comptes locaux adminpme et it-support avec mots de passe faibles, fichier credentials en clair sur le bureau.

WinRM actif par défaut, LocalAccountTokenFilterPolicy configuré, firewall ouvert sans restriction — accès shell administrateur complet à distance réservé aux comptes réellement membres du groupe Administrateurs local.

adminpme ([MOT_DE_PASSE_MASQUE]) confirmé actif mais SANS appartenance au groupe Administrateurs (validé recon 20 août 2026) — accès SMB/IIS/MariaDB fonctionnel, mais pas de shell WinRM admin. Erreur d'administration simulée : compte créé et diffusé comme « admin PME » sans jamais être ajouté au groupe.


## 7.8 Chemin de compromission totale


DNS (reconnaissance) → FTP anonyme ou fichiers bureau (credentials) → WinRM (exécution de commandes avec droits admin) → contrôle total de SRV2 (fichiers, base de données, IIS, persistance).


# 8. Glossaire technique


Terme

Définition

AXFR

Zone Transfer — mécanisme DNS de copie complète d'une zone vers un serveur secondaire ; dangereux s'il n'est pas restreint.

Récursion DNS

Capacité d'un serveur DNS à résoudre des requêtes pour des zones qu'il n'héberge pas, en interrogeant d'autres serveurs pour le compte du client.

DNSSEC

Extension de sécurité DNS permettant de signer cryptographiquement les enregistrements pour en garantir l'authenticité.

Basic Auth

Méthode d'authentification HTTP encodant les identifiants en Base64 — non chiffré sans HTTPS.

FTP anonyme

Mode d'authentification FTP acceptant une connexion sans identifiants valides (utilisateur « anonymous »).

WinRM

Windows Remote Management — service de gestion à distance basé sur WS-Management, utilisé par PowerShell Remoting.

PSRemoting

PowerShell Remoting — exécution de commandes PowerShell sur une machine distante via WinRM.

LocalAccountTokenFilterPolicy

Clé de registre déterminant si un compte administrateur local obtient un jeton complet (full token) lors d'une authentification réseau distante, plutôt qu'un jeton filtré (UAC remote restriction).

X-Backend-Server

En-tête HTTP personnalisé ajouté dans ce lab pour simuler une fuite d'information réseau (nom fictif, non standard).


# 9. Références croisées


Document

Lien avec ce document

05.1_DOC-SRV2-001

Bilan technique initial de SRV2 — failles Réseau, MariaDB, SMB, IIS et Comptes dont dépend cet addendum.

01.4_INFRASTRUCTURE_HYPERV (v2.1)

Architecture réseau confirmant l'isolation de SRV2 derrière SRV1 (double NAT) et le durcissement de SRV1 non affecté par cet addendum.

02.x_Durcissement SRV1

Référence de contraste : politique de durcissement appliquée à SRV1, volontairement non répliquée sur SRV2 (cible Red Team).


# 10. Historique des révisions


Version

Date

Description

Auteur

1.0

2026-08-17

Création de l'addendum — rôle DNS, fuite IP HTTP, FTP anonyme, confirmation WinRM

M. Belkacemi

1.1

2026-08-20

Validation par reconnaissance externe (Parrot OS) — ajout section 12. Correction section 6 : adminpme non membre du groupe Administrateurs, chaîne WinRM invalidée empiriquement et requalifiée en vecteur théorique. Ajout note brute-force non exécuté (section 12.4).

M. Belkacemi


# 11. Règle du projet


Aucun exploit, malware ou modèle IA orienté offensive security pure (ex. WhiteRabbitNeo, modèles « abliterated » pour le hacking) n'est développé ou assisté dans le cadre de ce projet. L'objectif est de comprendre les mécanismes de sécurité et de reproduire des erreurs de configuration réalistes et documentées, dans un environnement isolé, à des fins pédagogiques Red Team / Blue Team.
