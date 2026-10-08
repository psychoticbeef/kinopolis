# Kinoticket-Wächter

Ein kleines Bash-Tool für Linux: `curl` lädt die Filmseite, `awk` liest kaufbare
OV-Vorstellungen aus. Kein Python, Node, Browser oder `jq`.
Benötigt Bash, curl und übliche Linux-Werkzeuge inklusive `flock` (util-linux).

## Nix

```sh
nix develop                  # Bash, curl, awk, flock und Git
nix flake check              # lokale Tests, ohne externe Meldungen
nix run . -- status
nix run . -- check
```

Die Flake unterstützt x86_64-/aarch64-Linux und aarch64-macOS.
Das installierte Paket speichert Zustand unter
`${XDG_STATE_HOME:-$HOME/.local/state}/kino-watch`, nicht im Nix Store.
`KINO_CONFIG`, `KINO_STATE_DIR` und `KINO_NOTIFY` bleiben überschreibbar.

### NixOS: stündlich mit Pushover

Die Flake exportiert `nixosModules.default`. Im NixOS-Flake als Input aufnehmen
und das Modul importieren:

```nix
# flake.nix
inputs.kinopolis.url = "github:psychoticbeef/kinopolis";
# In den Modulen des Hosts:
# inputs.kinopolis.nixosModules.default
```

```nix
services.kino-watch = {
  enable = true;
  pushoverEnvironmentFile = config.sops.secrets."kinopolis-pushover-env".path;
};
```

Die Secret-Datei muss diese beiden Variablen enthalten (systemd-EnvironmentFile,
kein Shell-Skript):

```text
PUSHOVER_TOKEN=...
PUSHOVER_USER=...
```

Zugangsdaten nur zur Laufzeit aus einem Secret-Manager laden, niemals per
Nix-String oder Nix-Pfad im Store speichern. Die Filmkonfiguration kann mit
`services.kino-watch.configFile` überschrieben werden.

Der Timer läuft stündlich mit bis zu fünf Minuten zufälliger Verzögerung;
verpasste Läufe werden beim Start nachgeholt. Zustand bleibt in
`/var/lib/kino-watch` erhalten. Nach einer Meldung pausiert der jeweilige Film
wie beim manuellen Betrieb.

```sh
systemctl list-timers kino-watch.timer
journalctl -u kino-watch.service
sudo systemctl start kino-watch.service  # echter Check, kann Pushover senden
```

## Start

```sh
chmod +x kino-watch hooks/stdout tests/run
./kino-watch check
./kino-watch status
```

Die mitgelieferte Konfiguration `watches.tsv` enthält beide gewünschten Filme:

* `available`: meldet beim ersten Lauf mit kaufbaren OV-Vorstellungen.
* `new`: speichert beim ersten erfolgreichen Lauf den aktuellen Stand ohne
  Meldung. Spätere zusätzliche kaufbare OV-Vorstellungen lösen aus.

Ein Slot ist eine Vorstellung mit eigener Kinopolis-ID und Kauflink. OV wird
innerhalb der Vorstellung geprüft; die allgemeine OV-Legende zählt nicht.
OmU zählt nicht automatisch als OV. Das Tool prüft keine einzelnen Sitzplätze
und bewertet keine Sitzqualität. Frei werdende Plätze in bekannten Vorstellungen
lösen keine Meldung aus. Ein Kauflink zeigt die Buchungsmöglichkeit der Seite;
das Tool prüft keinen vollständigen Checkout.

## Pause und Reaktivierung

Nach erfolgreicher Meldung pausiert **der betroffene Film** automatisch.
Alle im Trefferlauf gefundenen kaufbaren OV-IDs werden gemeinsam gespeichert.
Andere Filme laufen weiter. Bekannte IDs bleiben auch gespeichert, wenn eine
Vorstellung zwischenzeitlich verschwindet; ihre Rückkehr erzeugt keinen Alarm.

```sh
./kino-watch rearm avengers-doomsday
./kino-watch pause street-fighter
./kino-watch baseline avengers-doomsday
```

`rearm` aktiviert den Film mit seinem bisherigen Stand. Beim nächsten Check
werden auch neue Vorstellungen erkannt, die während der Pause hinzugekommen
sind. `baseline` lädt die Seite, nimmt alle aktuellen OV-Vorstellungen als
bekannt auf und aktiviert den Film ohne Meldung. Das eignet sich, wenn die
jetzigen Plätze uninteressant sind und erst weitere Vorstellungen zählen sollen.
`baseline` und `pause` verwerfen eine eventuell ausstehende Meldung explizit.
`rearm` auf einem aktiven Film bewahrt eine ausstehende Meldung.

Zustand liegt standardmäßig in `state/`. Nicht löschen, wenn bekannte
Vorstellungen bekannt bleiben sollen. Ein Wechsel der URL braucht eine neue
Film-ID. Der Modus lässt sich ändern; ein bestehender Ausgangsstand bleibt dabei
erhalten. Bei fehlerhaftem Abruf oder nicht erkanntem HTML bleibt der Stand
unverändert, der Lauf endet mit Fehler. Pausierte Filme werden nicht abgerufen.

## Benachrichtigung anhängen

Standardmäßig schreibt `hooks/stdout` die Meldung auf stdout. Das gilt als
erfolgreiche Zustellung und pausiert den Film, auch beim manuellen Probelauf.
Zum Schauen ohne Meldung dient `baseline ID`.

Mit `KINO_NOTIFY` wählst du ein ausführbares Programm, ohne Argumente:

* stdin: Meldung mit Film- und direkten Vorstellungslinks.
* `KINO_WATCH_ID`: Film-ID.
* `KINO_FILM_URL`: Filmseite.
* `KINO_EVENT_ID`: feste Ereignis-ID, bei Zustellwiederholungen gleich.
* Exit 0: zugestellt, Film pausieren. Anderer Exit-Code: später erneut versuchen.

Ein Mail-Hook könnte so aussehen:

```sh
#!/bin/sh
exec mail -s "Kinotickets: $KINO_WATCH_ID" deine-adresse@example.org
```

Ein Pushover-Hook liegt unter `hooks/pushover.example`:

```sh
chmod +x hooks/pushover.example
export PUSHOVER_TOKEN='dein-app-token'
export PUSHOVER_USER='dein-user-key'
export KINO_NOTIFY='/opt/kino-watch/hooks/pushover.example'
./kino-watch check
```

Fehlgeschlagene Zustellungen werden mit derselben gespeicherten Meldung erneut
versucht, auch wenn die Seite danach andere Vorstellungen zeigt. Der globale
Lock verhindert parallele Läufe; Zustand wird per Dateiumbenennung ersetzt.
Nach erfolgreicher Zustellung gibt es im normalen Betrieb keine Wiederholung.
Ein Prozessabbruch zwischen externer Zustellung und lokalem Speichern kann
allerdings eine Wiederholung auslösen. Strikt einmalige externe Zustellung
braucht einen Hook/Empfänger, der `KINO_EVENT_ID` dedupliziert. SMTP und der
mitgelieferte Pushover-Hook garantieren das nicht. Bei unklarer Zustellung kannst
du mit `pause ID` einen automatischen Wiederholungsversuch verhindern.

## Stündlich per cron

Tool z. B. nach `/opt/kino-watch` kopieren, als normalen Benutzer starten.
Absolute Pfade verwenden; die Beispiele setzen Schreibrechte für den Zustand
und das Log voraus. In `crontab -e`:

```cron
0 * * * * /opt/kino-watch/kino-watch check >> /home/DEINUSER/kino-watch.log 2>&1
```

Für einen eigenen Hook und einen anderen Zustandsordner:

```cron
KINO_NOTIFY=/home/DEINUSER/bin/kino-notify
KINO_STATE_DIR=/home/DEINUSER/.local/state/kino-watch
0 * * * * /opt/kino-watch/kino-watch check >> /home/DEINUSER/kino-watch.log 2>&1
```

`KINO_CONFIG` überschreibt den Konfigurationspfad. Zugangsdaten für einen Hook
z. B. in einer nur für den Benutzer lesbaren Datei im Hook laden; cron übernimmt
nicht automatisch Variablen aus deinem interaktiven Terminal.

## Prüfung

```sh
./tests/run
```

Die Tests verwenden lokale HTML-Beispiele und einen Fake-Abruf; es werden keine
Nachrichten extern versendet. Getestet werden OV vs. deutsche/OmU-Vorstellungen,
Legende, fehlender Kauflink, beide Modi, neue IDs, Pause/Rearm, Parser-/Abruffehler
und erneute Zustellung mit gleicher Ereignis-ID. Wenn `flock` vorhanden ist,
wird auch die Sperre überlappender Läufe geprüft.

Der Parser ist bewusst auf das beobachtete Kinopolis-HTML beschränkt. Bei einer
Website-Umstellung kann eine Anpassung nötig sein; er ist kein allgemeiner
HTML-Parser.
