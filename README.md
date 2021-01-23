# fhemHPSU
FHEM Module to communicate with a Rotex HPSU

Changelog:

1.0 # 19.12.19
- Initiale Version
- Es können Paramater gelesen und gesetzt werden.

1.1 # 05.01.19
- Neue Funktionen: AntiMixerSwing, ForceDHW, CheckDHWInterrupted
- Neues Reading: Info.Q (aktuell generierte Energie)

1.2 # 13.01.20
- CheckDHWInterrupted und AntiMixerSwing optimiert
- Initialisierung für einen ELM327 mit Werkseinstellung angepasst

1.3 # 01.02.20
- Warnings eliminiert
- CheckDHWInterrupted und AntiMixerSwing optimiert

1.4 # 09.02.20
- "use JSON" and "use SetExtensions" ergänzt
- Timeout Zähler

1.5 # 27.09.20
- Bedingungen für AntiMixerSwing geändert (Direkter_Heizkreis_Modus und Modus)
- ForceDHW: Zieltemp. aus Reading t_dhw_setpoint1 anstatt t_dhw_set

1.6 # 05.10.20
- Request merken, damit bei mehreren Responses auch nur der geparsed wird 
    -> Durch das kann nun auch func_heating, quiet_mode, hc_func... abgefragt und gesetzt werden
- Neue Funktion: Connect_MonitorMode
- ForceDHW: Warten bis Que leer ist, damit auch die kurz vor ForceDHW gesetzte Zieltemp. verwendet wird.

1.7 # 11.12.20
- Neues Reading: Info.HeatCyclicErr (Anzahl Startvorgänge um takten zu erkennen)
- Neues Argument für DebugLog: onDHW

1.8 # 31.12.20
- Neue Funktion: AntiContinousHeating

1.9 # 05.01.21
- AntiContinousHeating: Frostschutz temporär ausschalten
- Negative Floatwerte zum Setzen eingebaut
- Bei "set" den Min/Max check fertiggestellt
- Achtung: Die JSON Dateil ab V3.6 wird benötigt!

1.10 # 07.01.21
- AntiContinousHeating: Reading Frostschutz schon beim Aktivieren des ACH Attributes einlesen, sonst gibts' beim ersten Ausführen einen Fehler
- Bei "set" den Min/Max check korrigiert

1.11 # 14.01.21
- Set und get verstehen ab jetzt ID oder NAMEN...
- Init setzt DHWForce zurück, falls das aktiv ist
- Neues Reading: Info.LastDefrostDHWShrink (verringerung der WW Temp. beim letzten Abtauvorgang)
- Neues Attribut: SuppressRetryWarnings (retries nicht loggen)
- Neues Attribut: RememberSetValues (den zuletzt gesetzten Modus beim Init senden)

1.12 # 24.01.21
- Modus Monitor_Mode: Erweiterung mit der Ausgabe des Headers im Readingnamen, In der Readingsvalue Bits entfernt aber Msg hinzugefügt, Float auch ins negative
