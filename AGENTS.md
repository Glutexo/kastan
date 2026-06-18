# Pravidla pro agenty

Tento soubor obsahuje projektova pravidla pro agenty pracujici v repozitari `jizdni-nerady`.
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
- Pred odevzdanim zkontroluj `git status`.

## Kvalita zmen

- Preferuj jednoducha, citelna reseni pred zbytecnymi abstrakcemi.
- Veskery napsany kod dokumentuj z pohledu produktu; dokumentace musi byt soudrzna, uplna a v souladu s implementovanymi funkcemi a vlastnostmi.
- Pri zmene chovani aktualizuj souvisejici dokumentaci a zaroven over, ze kod odpovida dokumentovanym funkcim a vlastnostem.
- Pridavej testy u zmen, ktere meni chovani nebo mohou rozbit existujici funkcnost.
- Pokud testy nejdou spustit, uved duvod a co zustava neoverene.

## Styl CLI

- Vystup na prikazove radce ma co nejverneji zachovavat vyznamove informace z IDOSu.
- Pokud HTML vysledek IDOSu obsahuje barvu pro linku nebo jiny prvek, CLI ma pouzit odpovidajici ANSI barvu.
- Barevne formatovani nesmi nahrazovat textovy obsah; vystup musi zustat srozumitelny i bez barev.
