# KOMPANIA — dokument projektowy (MVP)

Turowa gra o dowodzeniu kompanią najemników. Inspiracja: Mount & Blade,
uproszczona pod telefon i krótkie sesje. Bez real-time — walka to ekran
decyzji taktycznych. Priorytet wg autora: **1) dowodzenie i taktyka,
2) fabuła i frakcje, 3) ekonomia, 4) eksploracja.**

---

## 1. PĘTLA ROZGRYWKI (rdzeń)

```
Podróżuj po mapie węzłów  →  natrafiasz na wrogów / kontrakty / miasta
        ↓                                    ↓
   WALKA (decyzje taktyczne)          werbunek / handel / questy
        ↓                                    ↓
   łupy, ranni, doświadczenie  →  rozwój kompanii  →  większe wyzwania
        ↓
   wybór frakcji  →  wciągnięcie w wojnę  →  fabuła rozdziału
```

Sesja "do autobusu": jedna podróż + jedna walka + zarządzanie = 2-5 minut.
Stan zapisuje się po każdej akcji (dziedziczymy zapis z farmy).

---

## 2. WALKA — SERCE GRY (najważniejsze)

Turowa, oparta na decyzjach, nie na zręczności. Prototyp matematyczny
już potwierdził, że wybór postawy realnie zmienia szanse (12%–48% przy
tej samej armii) — jest głębia, ale i losowość.

### Skład oddziału
Trzy typy jednostek (na start), model kamień-papier-nożyce:
- **Piechota** — trzon, trzyma linię, tania
- **Łucznicy** — rażą z dystansu, kruche w zwarciu
- **Kawaleria** — miażdży w szarży, słaba w obronie/oskrzy­dleniu

### Przebieg bitwy (tury)
Każda bitwa to 3-5 tur. W każdej turze:
1. Widzisz swój oddział, wroga (szacunkowo — "mgła wojny"), teren
2. Wybierasz **postawę** na tę turę:
   - **Szarża** — premia kawalerii, ryzyko przy braku jazdy
   - **Linia** — premia piechoty, bezpieczna, zbalansowana
   - **Oskrzydlenie** — premia łuczników, dobra przeciw piechocie
3. Rozstrzygnięcie tury: straty po obu stronach wg sił i postaw
4. Morale — gdy spadnie za nisko, słabsza strona ucieka (koniec bitwy)

### Po bitwie
- **Łupy** (złoto, ekwipunek) proporcjonalne do siły wroga
- **Ranni vs zabici** — część strat to ranni (wracają po odpoczynku),
  część ginie na stałe. Lepszy wynik = więcej rannych, mniej zabitych.
- **Doświadczenie** — jednostki awansują (piechota → weterani → elita)
- **Sława** — waluta reputacji, otwiera lepsze kontrakty i frakcje

---

## 3. KOMPANIA (rozwój — druga w kolejności ważności)

- **Liczebność** — limit zależny od sławy i przywództwa dowódcy
- **Awanse jednostek** — rekrut → żołnierz → weteran → elita
  (przez przeżyte bitwy). Widoczny, satysfakcjonujący postęp.
- **Żołd** — jednostki kosztują złota za dzień; brak wypłaty = spadek morale
- **Dowódca (gracz)** — kilka prostych cech: Przywództwo (limit ludzi),
  Taktyka (premia w walce), Handel (lepsze ceny). Rosną z poziomem.

---

## 4. FABUŁA I FRAKCJE (druga w rankingu autora)

- **2-3 frakcje** w regionie, w stanie napiętego pokoju/wojny
- Zaczynasz jako **niezależny najemnik** — bierzesz kontrakty od obu stron
- **Sława** i wybory pchają Cię ku jednej frakcji → w końcu przysięgasz
  wierność → wciągnięcie w ich wojnę → fabuła rozdziału 1
- Questy jak w farmie: dostarczone przez "posłańców" (dziedziczymy mailbox
  jako system rozkazów/listów), z flagami i rozgałęzieniami
- **Rozdział 1** — prosty łuk: od bezimiennego najemnika do dowódcy, który
  musi wybrać stronę w nadciągającej wojnie. Cliffhanger na rozdział 2.

---

## 5. MAPA I EKONOMIA (podłoże)

### Mapa węzłów (nie swobodny teren — prościej i czytelniej na telefonie)
- Węzły: **miasta** (handel, kontrakty, werbunek elit), **wioski**
  (tani werbunek, zaopatrzenie), **obozy/ruiny** (walki, łupy)
- Krawędzie = drogi. Podróż między węzłami zajmuje "dni" (scheduler z farmy)
- Na drogach: losowe spotkania (wrogowie, kupcy, wędrowcy z questami)

### Ekonomia
- **Złoto** — żołd, werbunek, ekwipunek, łapówki
- **Zaopatrzenie** (jedzenie) — kompania je każdego dnia; brak = spadek morale
- Handel prosty: kupuj tanio w jednym mieście, sprzedawaj drogo w innym
  (opcjonalne źródło dochodu, nie wymuszone)

---

## 6. CO DZIEDZICZYMY Z FARMY (nie zaczynamy od zera!)

Solidny fundament pure-Dart, który już działa i jest przetestowany:
- **Zapis/wczytywanie** (SharedPreferences, wersjonowany klucz)
- **FlagStore** — flagi questowe z rozgałęzieniami
- **Scheduler** — zdarzenia w czasie (podróże, terminy kontraktów)
- **Mailbox** → przemianowany na **rozkazy/listy** (kontrakty, wieści)
- **ContentLoader** — treść questów w JSON, dwujęzyczna (PL/EN)
- **LocaleNotifier + AppStrings** — cały system i18n
- **Ekonomia** — kupno/sprzedaż, waluta, ekwipunek
- Architektura: czysty silnik Dart oddzielony od warstwy UI

## 7. CZEGO NIE MA W MVP (świadomie odcięte)

- Real-time bitwy (zastąpione turowymi decyzjami)
- Swobodna mapa 3D (zastąpiona mapą węzłów)
- Oblężenia, zamki, polityka dworska (rozdział 2+)
- Małżeństwa, dynastie, zarządzanie lennem (poza zakresem)
- Symulacja setek jednostek (abstrahowana do liczb w oddziale)

---

## 8. STYL WIZUALNY (wnioski z farmy!)

**Kluczowa lekcja z farmy: nie budujemy nic, co wymaga pixel-perfect
dopasowania niespójnych assetów.** Ta gra jest z gruntu mniej zależna
od grafiki:
- Mapa węzłów = punkty, linie, ikony (rysowane w kodzie / proste sprite'y)
- Oddziały = karty / ikony z liczbami, nie animowane postacie na siatce
- Walka = ekran z paskami, liczbami, ilustracją tła i przyciskami decyzji
- Portrety/ikony jednostek = pojedyncze obrazki na jednolitym tle
  (jeśli generowane — jeden spójny zestaw, jeden styl, jak w szablonie
  promptu, który już mamy)

Zero izometrii, zero diamentów, zero zaczepień co do piksela.

---

## 9. PIERWSZY KROK (jeśli ruszamy)

Zbudować **rdzeń walki jako samodzielny, grywalny ekran** — zanim cokolwiek
innego. Jedna bitwa: Twój oddział vs wróg, 3-5 tur wyboru postaw,
rozstrzygnięcie, ekran wyniku. Jeśli TO jest satysfakcjonujące w dłoni,
reszta (mapa, ekonomia, fabuła) się na tym nadbuduje. Jeśli nie —
poprawiamy rdzeń, zanim zbudujemy wokół niego świat.

To jest odwrotność błędu z farmy (gdzie silnik świata powstał przed
sednem rozgrywki).
