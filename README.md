# portable.sn

Boutique e-commerce de téléphones et accessoires au Sénégal — **un seul fichier HTML autonome**, sans framework (HTML + CSS + JavaScript vanilla).

🔗 En ligne : https://portable-sn.vercel.app

## Fonctionnalités

- Catalogue de produits avec marques, prix en **FCFA**, gestion du stock
- Badges **HOT** et **promotions** (prix barré + pourcentage automatique)
- Recherche en direct + filtre par catégorie (Samsung, Apple, Xiaomi, Tecno…)
- **Panier** complet (quantités, total) persistant via `localStorage`
- **Favoris** persistants
- **Commande par WhatsApp** : récapitulatif envoyé automatiquement à la boutique
- Bouton WhatsApp flottant, retour en haut de page, navigation basse
- 100 % hors-ligne : aucune dépendance externe (images en SVG inline)

## Développement

Tout le code tient dans [`index.html`](index.html). Pour le modifier, ouvre simplement le fichier dans un navigateur (double-clic) — aucune compilation nécessaire.

### Personnalisation rapide

- **Numéro WhatsApp** : variable `WHATSAPP` en haut du `<script>`.
- **Produits / stock** : tableau `PRODUCTS` (id, marque, nom, prix, stock, `oldPrice`, `tag`).
- **Catégories** : tableau `CATEGORIES`.

## Déploiement

Site statique servi tel quel par **Vercel**. Chaque `git push` sur la branche principale déclenche un redéploiement automatique.
