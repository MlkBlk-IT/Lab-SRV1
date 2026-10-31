# Lab-SRV1

A documented personal cybersecurity lab built around Hyper-V, Windows Server and an isolated double-NAT network.

## Architecture

```
Internet -> NAT router/RRAS -> external switch -> SRV1
                                             |
                                      internal switch
                                             |
                                      SRV2 (vulnerable target)
```

- **SRV1** — Windows Server 2025, DHCP, DNS, RRAS/NAT, WSUS and Windows Admin Center.
- **SRV2** — an intentionally vulnerable Windows Server target used for assessment practice.

The lab runs on a Dell Latitude 5420 with an i7-1185G7, 32 GB RAM and Intel Iris Xe graphics.

## Repository map

- `00_Fondations_Systeme/` — host preparation and reinstall planning
- `01_Architecture_Reseau/` — isolated Hyper-V network design
- `02_Securite_Hardening/` — SRV1 hardening documentation and scripts
- `03_Identite_Domaine_AD/` — Active Directory planning
- `04_Scripts_PowerShell/` — maintenance, audit and security automation
- `05_Audits_et_Logs/` — audit scripts and logs
- `06_Virtual_Machines/` — SRV2 documentation and assessment notes

## Method

The lab keeps the hardened server and vulnerable target separate. Changes, tests and evidence are documented so the environment can be rebuilt instead of treated as a black box.

## Scope

This is a private lab for systems I control. The vulnerable target is intentionally isolated and must not be exposed to an untrusted network.

## Status

Ongoing documentation and hardening work.

## Author

Built by [Malik Belkacemi](https://github.com/MlkBlk-IT).
