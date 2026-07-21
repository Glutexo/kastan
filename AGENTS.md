# Pravidla pro agenty

Tento soubor obsahuje projektova pravidla pro agenty pracujici v repozitari `kastan`.
Pravidla budeme prubezne rozsirovat.

## Zakladni chovani

- Komunikuj cesky, pokud uzivatel nezada jinak.
- Pred upravami si nejdriv over stav repozitare a existujici soubory.
- Drz zmeny co nejbliz pozadavku; nesouvisejici refaktoring nech stranou.
- Nemen ani nevracej cizi rozpracovane zmeny bez vyslovneho pokynu.
- Kdyz si nejsi jisty rozsahem nebo dopadem zmeny, nejdriv se zeptej.

## Git a GitHub

- Neprovadej destruktivni git operace bez vyslovneho souhlasu.
- Vsechny dokoncene zmeny hned commituj a pushuj na GitHub, pokud uzivatel vyslovne nerekne jinak.
- Po kazde zmene zkontroluj, zda reprezentativni snimek aplikace v README zustava aktualni. Pokud ho zmena zneaktualni, zaloz pred odevzdanim GitHub issue pro jeho obnoveni.
- Reprezentativni snimek aplikace v README nesmi nikdy obsahovat spoje dopravce RegioJet.
- Pred odevzdanim zkontroluj `git status`.

## Kvalita zmen

- Preferuj jednoducha, citelna reseni pred zbytecnymi abstrakcemi.
- Verejna rozhrani projektu zatim pojmenovavej anglicky, vcetne CLI prikazu, voleb, knihovniho API a dokumentovanych prikladu.
- Pri anglickem nazvoslovi pouzivej terminy z anglicke verze IDOSu, pokud pro danou vec existuji.
- Veskery napsany kod dokumentuj z pohledu produktu; dokumentace musi byt soudrzna, uplna a v souladu s implementovanymi funkcemi a vlastnostmi.
- Pri zmene chovani aktualizuj souvisejici dokumentaci a zaroven over, ze kod odpovida dokumentovanym funkcim a vlastnostem.
- Pridavej testy u zmen, ktere meni chovani nebo mohou rozbit existujici funkcnost.
- Pokud testy nejdou spustit, uved duvod a co zustava neoverene.

## Dokumentace

- `README.md` udrzuj jako strucnou, uzivatelsky privetivou vstupni stranku produktu. Patri do nej hlavni prinos,
  podporovana rozhrani, reprezentativni snimek, nejkratsi cesta ke spusteni a odkaz na uplnou dokumentaci;
  nepatri do nej vycerpavajici seznamy vlastnosti, voleb nebo API.
- `docs/README.md` je rozcestnik uplne dokumentace. Podrobne pruvodce jednotlivych rozhrani udrzuj jako
  kanonicky a uplny popis jejich vlastnosti, chovani, pozadavku a prikladu.
- Pri zmene chovani aktualizuj prislusny podrobny pruvodce. README men jen tehdy, kdyz se meni celkove zamereni,
  podporovane rozhrani, hlavni pozadavky nebo nejkratsi cesta ke spusteni.
- Nove verejne rozhrani dostane vlastniho pruvodce v `docs/` a odkaz v `docs/README.md`. Podrobnosti mezi README
  a pruvodci zbytecne neduplikuj.

## Styl CLI

- Vystup na prikazove radce ma co nejverneji zachovavat vyznamove informace z IDOSu.
- Pokud HTML vysledek IDOSu obsahuje barvu pro linku nebo jiny prvek, CLI ma pouzit odpovidajici ANSI barvu.
- Barevne formatovani nesmi nahrazovat textovy obsah; vystup musi zustat srozumitelny i bez barev.
- Pro symboly ve vystupu preferuj Unicode znaky pred ASCII nahradami, napr. `→` misto `->`.
- Ve vystupu CLI pouzivej emotikony jako rychle vizualni znacky stavu nebo typu informace, ale nesmi nahrazovat srozumitelny text.
