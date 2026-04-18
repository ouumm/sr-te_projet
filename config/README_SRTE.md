# SR-TE Lab — OSPF-TE, SR-MPLS & Stateful PCE (IOS-XRd)

Ce lab démontre l’utilisation conjointe de **Segment Routing MPLS (SR-MPLS)**, **OSPF-TE**, **Flex-Algo** et d’un **PCE stateful (PCEP)** pour le calcul et l’instanciation de politiques **SR-TE dynamiques et explicites**.

Il est conçu pour fonctionner sur **Cisco DevNet Sandbox / XRd** à l’aide de Docker.

---

## Objectifs du lab

- Mettre en œuvre SR-MPLS avec OSPF
- Comparer différents types de chemins :
  - IGP classique (algo 0)
  - Flex-Algo basé sur la latence
  - SR-TE explicite
  - SR-TE dynamique piloté par un PCE

- Utiliser :
  - BGP-LS pour alimenter la TED du PCE
  - PCEP stateful pour le calcul et la gestion des SR Policies

- Démontrer le steering du trafic par **Color Extended Community**

---

## Topologie

```
              pce (100.100.100.107)
               |
           [GE2]router2[GE1]
          /                 \
pc1--router1             router4--pc2
          \                 /
           [GE1]router3[GE1]
```

### Caractéristiques des chemins

| Chemin         | IGP Metric | Delay  |
| -------------- | ---------- | ------ |
| TOP (R1–R2–R4) | 20         | 200 µs |
| BOT (R1–R3–R4) | 40         | 20 µs  |

- Le chemin **TOP** est préféré par l’IGP
- Le chemin **BOT** est préféré par le **Flex-Algo 128 (delay)**

---

## Rôle des nœuds

| Nœud    | Rôle             |
| ------- | ---------------- |
| router1 | Ingress PE + PCC |
| router2 | Transit P        |
| router3 | Transit P        |
| router4 | Egress PE + PCC  |
| pce     | PCE stateful     |

---

## Segment Routing – SIDs

| Nœud    | Loopback        | Algo 0 SID | FA128 SID | FA129 SID |
| ------- | --------------- | ---------- | --------- | --------- |
| router1 | 100.100.100.101 | 16101      | 16201     | 16301     |
| router2 | 100.100.100.102 | 16102      | 16202     | 16302     |
| router3 | 100.100.100.103 | 16103      | 16203     | 16303     |
| router4 | 100.100.100.104 | 16104      | 16204     | 16304     |
| pce     | 100.100.100.107 | 16107      | –         | –         |

---

## Politiques SR-TE implémentées

| Color | Type     | Chemin       | Calcul                      |
| ----- | -------- | ------------ | --------------------------- |
| 100   | Dynamic  | R1 → R2 → R4 | PCE – IGP metric            |
| 128   | Dynamic  | R1 → R3 → R4 | PCE – Flex-Algo 128 (delay) |
| 200   | Explicit | R1 → R2 → R4 | SID list statique           |
| 300   | Explicit | R1 → R3 → R4 | SID list statique           |

- Les politiques **100** et **128** sont **on-demand** et calculées par le PCE
- Les politiques **200** et **300** sont **locales**, sans intervention du PCE

---

## Control Plane

### OSPF

- OSPF Area 0
- OSPF-TE activé
- Segment Routing MPLS
- Flex-Algo :
  - 128 : delay
  - 129 : TE metric

### BGP

- VPNv4 iBGP direct entre router1 et router4
- BGP-LS entre les PCCs et le PCE pour la construction de la TED

### PCEP

- PCE stateful
- PCCs : router1 et router4
- Capacités :
  - Stateful
  - Update
  - Instantiation
  - Segment Routing

---

## Déploiement (XRd Sandbox)

### Préparation

```bash

```

Génération du fichier docker-compose :

```bash
xr-compose \
  --input-file docker-compose_srte.yml \
  --output-file docker-compose.yml \
  --image ios-xr/xrd-control-plane:25.3.1
```

Adaptation de l’interface de management du sandbox :

```bash
sed -i.bak 's/linux:xr-120/linux:eth0/g' docker-compose.yml
```

---

### Lancement

```bash
docker-compose up -d
```

Temps de boot typique : 4 à 5 minutes.

---

### Accès aux équipements

Identifiants :

```
cisco / C1sco12345
```

```bash
ssh cisco@172.30.0.101   # router1
ssh cisco@172.30.0.102   # router2
ssh cisco@172.30.0.103   # router3
ssh cisco@172.30.0.104   # router4
ssh cisco@172.30.0.107   # pce
```

---

## Steering du trafic (principe)

Le steering repose sur :

- l’Extended Community **Color** dans les routes VPNv4
- l’instanciation automatique de **SR Policies on-demand**

Exemple de fonctionnement :

- router4 exporte une route VRF avec la couleur 100
- router1 déclenche automatiquement une SR Policy color 100
- le PCE calcule et instancie le chemin correspondant

---

## Contenu du repository

```
.
├── docker-compose_srte.yml
├── router1-startup.cfg
├── router2-startup.cfg
├── router3-startup.cfg
├── router4-startup.cfg
├── pce-startup.cfg
└── README.md
```

---

## Cas d’usage couverts

- Comparaison IGP vs routing basé sur la latence
- Flex-Algo avec SR-MPLS
- SR-TE dynamique via PCE stateful
- Politiques explicites vs dynamiques
- Interaction BGP-LS et PCEP

---

## Notes

-
