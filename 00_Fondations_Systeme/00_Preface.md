
# Préface : Laboratoire Cybersécurité Isolé (Lab-SRV1)


Environnement matériel : Dell Latitude 5420 (i7, 32 Go RAM, SSD NVMe)Hyperviseur : Hyper-V & WSL2Système Cœur : Windows Server 2025

Projet de fin d'études — DEP Soutien Informatique (EMICA) | Auteur : Malik Belkacemi

🛡️ ENGAGEMENT DE TRANSPARENCE & RÉALISATIONL'intégralité du travail technique, de l'ingénierie d'architecture, du diagnostic, de la rédaction des scripts et de l'exécution documentée dans ce portfolio a été pensée et réalisée par moi-même à 100%. L'Intelligence Artificielle n'a été employée qu'en tant qu'assistante éditoriale pour formater, structurer et mettre en page mes notes brutes. Chaque décision architecturale, chaque règle de pare-feu, chaque concept « Ghost » et chaque résolution d'incident est le fruit exclusif de ma propre réflexion d'ingénieur.


# 1. L'Étincelle et l'Ampleur du Projet


Tout a commencé avec un constat simple et une frustration assumée : comment concevoir un véritable réseau d'entreprise, sécurisé, segmenté et réaliste, quand on ne dispose pour tout équipement que d'un unique ordinateur portable ? Ce projet, d'une ampleur massive pour un environnement mono-machine, n'avait pas pour seul but de valider mon DEP en Soutien Informatique. C'était un défi d'ingénierie : faire entrer une infrastructure d'entreprise complexe, avec ses domaines, ses failles et sa surveillance, dans 32 Go de RAM et un SSD NVMe.

Je voulais un terrain de jeu complet (Blue Team, Red Team, Purple Team) où je pourrais casser, analyser et reconstruire sans jamais compromettre la sécurité de ma machine physique. Les contraintes matérielles ne sont pas devenues un frein, mais le moteur d'une optimisation extrême.


# 2. La Philosophie « Ghost » : Furtivité et Contrôle Absolu


Ce projet ne se résume pas à empiler des machines virtuelles. C'est une démarche rigoureuse, presque obstinée, guidée par ce que j'appelle la philosophie « Ghost ». Dans ce laboratoire, la furtivité, le Zero Trust et l'isolation sont des dogmes absolus :

Isolation Totale (Zero Trust Hôte) : Le laboratoire opère dans une bulle hermétique via un double NAT. Zéro communication n'est autorisée entre l'hôte physique et les machines virtuelles. Le laboratoire est un fantôme pour l'ordinateur qui l'héberge.

Durcissement Furtif (Hardening by Design) : Le cerveau du réseau refuse tout trafic entrant par défaut. Pas de ports ouverts par commodité. Le système est rendu silencieux, limitant drastiquement sa surface d'attaque.

Maîtrise du Bas Niveau : Refuser la facilité des outils « clés en main ». Construire des scripts PowerShell idempotents, auditer avant d'agir, et prévoir des mécanismes de rollback (retour en arrière) chirurgicaux. Le contrôle sur l'environnement doit être total et documenté.


# 3. L'Écosystème Virtuel : Cartographie des Instances


Pour donner vie à cette infrastructure, j'ai segmenté les rôles à travers un parc de machines virtuelles spécialisées, chacune ayant une fonction vitale dans ma chaîne d'attaque et de défense :

SRV1 (Le Cerveau Fortifié) : Un Windows Server 2025 agissant comme routeur (RRAS), pare-feu, DHCP, DNS, et futur Contrôleur de Domaine (AD DS). Il est le gardien du réseau, durci à l'extrême, sur lequel repose toute la sécurité identitaire.

SRV2 (La Cible - PME Québec Inc.) : Un Windows Server 2022 volontairement mal configuré (IIS, MariaDB, mots de passe faibles, SMB ouvert). Il simule les erreurs classiques d'une petite entreprise et sert de terrain de jeu (Red Team) pour valider des kill chains.

L'Arsenal Périphérique : Des postes clients (Windows 10/11) pour simuler les utilisateurs, une machine Parrot OS pour les offensives cyber, un SIEM (Fedora Security) pour la corrélation des logs, et un Honeypot (Alma OS) pour piéger les menaces.


# 4. Ce que vous allez découvrir


Ce portfolio est conçu comme le carnet de route d'un architecte système et réseau. Vous n'y trouverez pas une simple succession de tutoriels, mais le récit d'un déploiement authentique, face aux contraintes du réel.

Vous y lirez mes doutes, l'évolution de mon architecture, mes diagnostics d'incidents (comme les conflits SMB post-durcissement) et mes correctifs appliqués via des scripts PowerShell faits maison. C'est un travail vivant, imparfait au départ, mais qui tend avec rigueur vers l'excellence opérationnelle. Bonne lecture.
