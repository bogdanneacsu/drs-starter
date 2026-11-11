# Scripturi online CSP (livrate de serverul ACSM)

Scripturile din acest folder **nu se instalează de piloți**. Serverul le trimite fiecărui client la conectare prin
`csp_extra_options.ini` (secțiunea `[SCRIPT_...]`). Valorile (de ex. linia de start) stau în configul serverului,
deci pilotul nu le poate schimba din aplicație.

## warm_tyres.lua
Ține anvelopele la temperatura optimă de la ieșirea din boxe până la `stopRadius` metri de linia de start.
Se reactivează la „back to pits” (între Run 1 și Run 2).

Exemplu (blocul exact îl copiezi din **DRS Organizer → Copiază pentru ACSM**):

```ini
[SCRIPT_...]
SCRIPT = https://raw.githubusercontent.com/bogdanneacsu/drs-starter/v1.0.0/online/warm_tyres.lua
startPos = X, Y, Z
stopRadius = 20
tempOffset = 0
```

Folosește întotdeauna un link către un **tag fix** (ex. `v1.0.0`), nu către `main`, ca serverul să trimită exact
versiunea verificată.

**Status:** scriptul este cel furnizat de organizator, neschimbat. Încărcarea din URL și `physics.setTyresTemperature`
într-un script online trebuie confirmate pe serverul ACSM 2.4.8 (PoC).
