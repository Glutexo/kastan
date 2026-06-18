# jizdni-nerady

Jízdní neřády jsou osobní Swift CLI pro občasné jednorázové dotazy do IDOSu.
Používají veřejně dostupné URL rozhraní webu IDOS a parsují vrácené HTML, takže nejde o stabilní ani garantované datové API.

## Použití

Našeptání názvu stanice nebo místa:

```sh
swift run jizdni-nerady suggest Praha
```

Vyhledání spojení:

```sh
swift run jizdni-nerady spojeni --from Praha --to Brno --date 18.6.2026 --time 12:00
```

Volitelně lze omezit počet vypsaných položek:

```sh
swift run jizdni-nerady spojeni --from Praha --to Brno --limit 3
```

Nástroj je určený pro nízkofrekvenční osobní použití. Pokud IDOS změní HTML nebo interní JSONP našeptávač, parser bude potřeba upravit.

## Vývoj

```sh
swift build
swift test
swift run jizdni-nerady
```
