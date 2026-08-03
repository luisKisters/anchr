# Anchr

Brainstorming-Dokument. **Kein Implementationsplan.** Hier steht, was die Idee ist,
was der Scope der ersten Version sein soll, und welche Fragen noch offen sind.

---

## An den Agent, der hier arbeitet

**Lies das zuerst, bei jeder Session.**

Der Owner dieses Projekts hat einen starken Action Bias: sofort losbauen, statt zu
planen, Scope unterwegs aufblasen, an mehreren Sachen gleichzeitig arbeiten. Das
ist übrigens genau das Problem, das diese App lösen soll, und es gilt auch für die
Entwicklung der App selbst.

Deine Aufgabe als Agent:

- **Verteidige den kleinen Scope aktiv.** Wenn eine Anfrage über den V1-Scope
  unten hinausgeht, sag das explizit, bevor du baust. Nicht refusen, aber
  benennen: "Das ist Post-V1 laut BRAINSTORM.md, willst du das wirklich jetzt?"
- **Ein funktionierender kleiner Kern schlägt fünf halbfertige Features.** Diese
  App hat besonders viele verlockende Features. Fast alle sind Post-V1.
- **Erst wenn V1 steht und der Owner sie täglich selbst benutzt**, wird über die
  Later-Liste geredet. Diese App ist Dogfooding pur: wenn sie ihn nicht
  überzeugt, überzeugt sie niemanden.
- Wenn eine neue Idee auftaucht: nicht bauen, sondern unten unter "Later /
  Parkplatz" eintragen.

---

## Die Idee in einem Satz

Eine macOS App, die alle paar Minuten per Screenshot schaut, woran man gerade
arbeitet, das gegen die aktuelle Aufgabe prüft, und bei Abweichung nachfragt,
statt einfach zu blocken.

## Warum

Der Ausgangspunkt ist ein sehr konkretes eigenes Problem: direkt in die Ausführung
springen, ohne vorher zu organisieren und zu planen, obwohl Planen in den meisten
Fällen mehr helfen würde. Also erst spezifizieren, wie man etwas ausführt, statt
sofort loszulegen.

## Das Kernkonzept: Arbeiten wie Meditieren

Das ist der wichtigste Gedanke im ganzen Dokument, alles andere hängt daran.

Die Idee stammt aus einem YouTube-Video: Man arbeitet auf eine Art, wie man
meditiert. Man schreibt eine Aufgabe auf und arbeitet an der. Wenn man merkt, dass
man von der Aufgabe abkommt, ärgert man sich nicht, sondern **macht die Aufgabe
spezifischer.**

Beispiel: Die Aufgabe ist "E-Mail schreiben". Man driftet ab. Statt sich zu
schelten, wird die Aufgabe granularer: "Erstmal den Kontakt raussuchen." Driftet
man wieder ab, wird sie noch granularer. Genau wie beim Meditieren, wo man die
Aufmerksamkeit einfach wieder zum Atem zurückführt, ohne Bewertung.

Eine AI, die diesen Schritt automatisch mitmacht und vorschlägt, wäre ein Game
Changer. Sie erkennt den Drift, bevor man ihn selbst merkt, und bietet an, die
Aufgabe zu verkleinern.

Daher auch der Name: **Anchr**, von "anchor". Die aktuelle Aufgabe ist der Anker.
Wenn man abdriftet, wird man zurückgeholt, oder der Anker wird kleiner und
konkreter gesetzt.

## Alle Ideen aus dem Brainstorming

**Beobachtung**

- Alle paar Minuten ein Screenshot, das Modell schaut, was man macht.
- Bewertung: Ist das relevant für die aktuelle Arbeit?
- Wenn nicht relevant: ein Fenster poppt auf und fragt, warum das gerade relevant
  ist. Man muss es erklären.
- Das Modell darf nachhaken: "Bist du ganz sicher, dass das relevant ist?" oder
  "Ist das gerade wirklich das Richtige?"
- Selbst wenn die App nur alle zehn Minuten fragt "ist das gerade produktiv?",
  hätte das schon Wert.

**Interface**

- Bevorzugt Voice Input. Man redet, statt zu tippen.
- Alles muss aber theoretisch auch per Text gehen, umschaltbar über einen Button.

**To-do-Liste als Kern**

- Man plant zu Beginn mit dem Tool eine Aufgabe oder ein Feature durch.
- Das Tool aktualisiert die To-do-Liste automatisch mit, sagt aber **immer**
  Bescheid, wenn es sie ändern will. Nie stillschweigend.
- Wenn man von der Aufgabe abgekommen ist, meldet es sich.
- Wenn die App merkt, dass man an einem anderen Feature arbeitet als geplant:
  fragen, ob man das jetzt abhaken will, oder ob die Liste angepasst werden soll.
- Wenn die App merkt, dass man an einem ganz anderen Projekt arbeitet: fragen, ob
  dafür eine eigene To-do-Liste angelegt werden soll.
- Vorschlag statt Befehl: "Du warst eigentlich an der Aufgabe X, lass die doch mal
  spezifischer machen, was genau musst du davon jetzt tun?"
- **Paralleles Arbeiten muss explizit unterstützt sein.** Mit AI Coding arbeitet
  man real an mehreren Sachen gleichzeitig. Eine App, die das als Fehler wertet,
  ist unbrauchbar.

**Modi**

- Verschiedene Härtegrade.
- Im härtesten Modus erlaubt die App teils gar nicht, bestimmte Apps zu öffnen,
  und schließt sie einfach wieder.

**Lernen und Coaching**

- Die App lernt über die Zeit, wie man sich verhält.
- Sie soll coachen, nicht bevormunden.

**Technik**

- macOS App.
- Voice per FluidAudio, lokal.
- LLM erstmal in der Cloud. Lokal wäre großartig, aber dafür sind die lokalen
  Modelle noch nicht gut genug.

**Externe Systeme (ausdrücklich als Später-Feature markiert)**

- Zugriff auf Obsidian: Aufgaben dort direkt abhaken und ändern.
- Generell: sich an den bestehenden Workflow anpassen, statt einen neuen zu
  erzwingen.

## Kooperation

Es gibt die Überlegung, das zusammen mit einem befreundeten Studio zu bauen. Der
Name Anchr ist bewusst eigenständig gewählt, damit die Idee unabhängig davon
funktioniert, ob eine Kooperation zustande kommt oder nicht.

---

## Scope: V1

Hart begrenzt. Diese App hat mehr verlockende Features als jedes andere Projekt
hier. Das Ziel von V1 ist: **der Owner benutzt sie eine Woche lang täglich selbst
und will sie danach nicht mehr abschalten.** Nicht mehr.

Vorschlag, was in V1 gehört:

- Eine aktuelle Aufgabe. Eine. Als Text eingegeben.
- Screenshot alle paar Minuten, ein LLM-Call, eine Frage: passt das zur Aufgabe?
- Wenn nein: ein kleines Fenster, das nachfragt. Antwort per Text reicht in V1.
- Der eine Move, der die App ausmacht: anbieten, die Aufgabe spezifischer zu
  machen.
- Sonst nichts.

Alles, was hier nicht steht, ist **nicht** V1. Insbesondere nicht: Voice, Modi,
App-Blocking, Lernen, Obsidian, mehrere Projekte, Planungs-Session.

Die härteste Frage für V1 lautet nicht "welche Features", sondern **"ist die
Drift-Erkennung per Screenshot überhaupt gut genug, dass sie nicht nervt?"** Wenn
die Antwort nein ist, ist der Rest der App egal. Das ist das Risiko, das V1
beantworten muss.

## Later / Parkplatz

Erst anfassen, wenn V1 steht und täglich benutzt wird.

- Voice Input per FluidAudio, plus Text-Umschalter
- Nachhaken durch das Modell, mehrstufiger Dialog
- Geführte Planungs-Session am Anfang einer Aufgabe
- Automatische To-do-Listen-Updates mit Rückfrage
- Mehrere parallele Projekte und Listen
- Erkennen, an welchem Projekt man gerade arbeitet, und die passende Liste ziehen
- Modi mit unterschiedlichem Härtegrad
- Apps blockieren und automatisch schließen
- Lernen des eigenen Verhaltens über Zeit, echtes Coaching
- Obsidian-Integration, Aufgaben abhaken und ändern
- Statistiken, Auswertung, Verlauf
- Lokales LLM statt Cloud

## Fragen, die noch geklärt werden sollten

- Wie oft ist "alle paar Minuten"? Zu oft nervt, zu selten hilft nicht. 5, 10, 15?
- Ganzer Screen oder nur die Frontmost-App? Ganzer Screen ist informativer, aber
  deutlich heikler.
- Was passiert mit den Screenshots? Werden sie gespeichert oder direkt verworfen?
  Vorschlag: direkt nach dem LLM-Call verwerfen, nichts persistieren. Das macht
  die App auch für andere Leute erträglich.
- Wie geht die App mit Meetings, Pausen und Recherche um, die legitim wie Drift
  aussieht?
- Wie verhindert man, dass die App zum Nörgler wird und man sie nach zwei Tagen
  abschaltet? Das ist das eigentliche Produktrisiko.
- Wie erkennt man "arbeitet an einem anderen Projekt" zuverlässig, ohne dass es
  jedes Mal falsch rät?
- Welches Cloud-Modell konkret, und was kostet ein Tag Nutzung realistisch?
- Braucht es Screen-Recording-Permission, und wie erklärt man die dem Nutzer?

## Namensherkunft

Anchr, von "anchor". Folgt dem gleichen Schema wie NoteTakr und Launchr: ein Nomen
auf `-er`, bei dem das `e` wegfällt. Die Metapher trägt bis in die UI, zum Beispiel
"dein aktueller Anker" statt "deine aktuelle Aufgabe".

---

## Anhang: Original-Brainstorming (Transkript, gekürzt)

Sprachaufnahme, leicht bereinigt. Persönliche Details entfernt.

> Meine Idee war, eine App, die quasi alle paar Minuten einen Screenshot macht und
> schaut, was du machst, und sagt, ob das relevant für die Arbeit ist. Und wenn
> nicht, poppt ein Fenster auf, was sagt: Okay, warum ist das relevant für deine
> Arbeit? Dann musst du es erklären, per Voice Input.
>
> Das Modell kann auch nochmal nachfragen und sagen: Ganz sicher, dass das
> relevant ist, oder dass das das Richtige ist? Das hilft generell mit meiner
> Arbeitsweise, weil ich einen starken Action Bias habe und vergesse, meine
> Aufgaben zu organisieren und zu planen, wie ich was arbeite, obwohl mir Planen
> oft mehr helfen würde. Also ein bisschen was auszuspecken und zu überlegen, wie
> ich das ausführe.
>
> Und was auch richtig geil wäre: wenn ich vorher mit dem Tool zusammen eine
> To-do-Liste schreibe, und das Tool aktualisiert meine To-do-Liste automatisch,
> sagt mir aber immer Bescheid, wenn es sie aktualisieren will, oder wenn ich von
> der Aufgabe abgekommen bin.
>
> Die Idee kam daher: Ich habe mal in einem YouTube-Video gehört, dass jemand
> meinte, dass man so ein bisschen so arbeitet, wie man meditiert. Also dass man
> eine Aufgabe aufschreibt und an der arbeitet. Wenn man merkt, dass man von der
> Aufgabe abkommt, macht man sie noch spezifischer. Sagen wir mal, ich soll eine
> E-Mail schreiben, und wenn ich da von der Aufgabe abkomme, macht man das noch
> spezifischer und sagt: Okay, ich suche erstmal den Kontakt raus, die
> E-Mail-Adresse suche ich erstmal raus. Quasi dass es immer granularer wird. Und
> eine AI, die das mit einem zusammen macht, das wäre einfach ein Game Changer.
>
> Allein wenn die AI einen jede zehn Minuten fragt, ob das gerade produktiv ist.
> Und ich glaube, was ich ein sehr geiles Interface finde, ist, wenn man alles
> theoretisch auch mit Text machen kann, aber das bräuchte einen Button, um das
> umzustellen, dass es preferably mit Voice Input ist und mit lokalen Modellen
> über FluidAudio läuft. Und es wäre auch krass, wenn die AI lokal laufen würde,
> aber ich glaube, dafür sind AIs noch nicht so weit, da würde ich einfach ein
> Cloud-Modell nehmen.
>
> Die App beobachtet einen quasi die ganze Zeit und fragt einen, ob das, was man
> macht, wirklich produktiv ist. Und je nach Modus erlaubt sie dir teils nicht,
> Apps zu öffnen, und schließt die Apps einfach wieder. Und sagt beispielsweise:
> Was ist jetzt deine nächste Aufgabe? Oder schlägt vor: Du warst gerade
> eigentlich an der Aufgabe da dran, lass das doch nochmal spezifischer sagen, was
> genau du jetzt von dieser Aufgabe machen musst.
>
> Also beispielsweise, wenn ich sage, ich muss ein Feature implementieren, und ich
> habe am Anfang mit der App einen Plan durchgeplant zu diesem Feature. Und dann,
> wenn die App merkt, okay, ich baue gerade irgendwas ganz anderes, arbeite an
> einem anderen Feature, dass sie dann sagen kann, dass ich auch an mehreren
> Features gleichzeitig arbeiten kann, weil das nun mal mit AI oft so ist, dass
> man an mehreren Sachen gleichzeitig arbeitet. Und dass sie dann sagt: Okay, du
> arbeitest wahrscheinlich gerade daran, willst du das jetzt abhaken? Oder wenn
> sie merkt, du arbeitest an einem anderen Projekt: Willst du dafür eine
> To-do-Liste erstellen? Oder auch, wenn ich irgendwas anderes mache als das, was
> im Plan steht, dass sie sagt: Hey, willst du deine To-do-Liste aktualisieren,
> oder solltest du vielleicht gerade eigentlich was anderes machen?
>
> Und dass die App lernt, wie man sich verhält, und einen darin coacht. Und was
> auch geil wäre, ist Zugriff auf externe Systeme, das ist vielleicht ein Feature
> für später, dass sie Zugriff auf mein Obsidian hat und darin Aufgaben abhaken
> und umändern kann und sich so an meinen Workflow anpasst. Das fände ich eine
> mega coole Idee.
>
> Bitte aggressiv scopen, was die erste Version ist, und was vielleicht Features
> sind, die man später machen kann, wenn die erste Version gut steht. Weil das ist
> so ein Bias, den ich schnell habe.
