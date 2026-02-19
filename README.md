# DriveSize - Analizator Przestrzeni Dysku (Panel Sterowania)

## Opis Projektu

DriveSize to wtyczka do Panelu Sterowania Windows (plik `.cpl`), której zadaniem jest skanowanie wszystkich lokalnych dysków twardych i prezentowanie rezultatu skanowania w formie interaktywnego wykresu kołowego oraz szczegółowej legendy.

Aplet pozwala użytkownikowi szybko zorientować się, które foldery zajmują najwięcej miejsca na dysku, bez konieczności instalowania zewnętrznych, ciężkich narzędzi.

## Główne Funkcje

- **Automatyczne Skanowanie**: Wykrywa i skanuje wszystkie partycje (dyski stałe) w systemie.
- **Wizualizacja Danych**: Prezentuje zajętość dysku na wykresie kołowym z podziałem na:
  - **Top 3 Foldery**: Trzy największe katalogi w głównym katalogu dysku.
  - **Inne (Other)**: Pozostałe zajęte miejsce.
  - **Wolne (Free)**: Dostępna przestrzeń.
- **Interaktywna Legenda**:
  - Każdy segment wykresu posiada "dymek" z opisem (nazwa, procent, rozmiar w GB).
  - **Dwukierunkowe Podświetlanie**: Najechaniem myszką na wycinek wykresu podświetla odpowiadający mu dymek i linię (na pomarańczowo-czerwono). Analogicznie, najechaniem na dymek podświetla wycinek na wykresie.
- **Wydajność**: Skanowanie odbywa się w tle, z mechanizmami zapobiegającymi zamrażaniu interfejsu (throttling odświeżania, asynchroniczne aktualizacje).

## Wymagania Systemowe

- System operacyjny: Windows 7, 8, 10, 11 (x86 lub x64).
- Uprawnienia Administratora (do instalacji w katalogach systemowych lub rejestracji).

## Instrukcja Instalacji i Wdrożenia

### 1. Kompilacja

Projekt jest napisany w środowisku Delphi. Aby zbudować plik wynikowy:

1.  Otwórz plik projektu `DriveSize.dpr` w IDE Delphi.
2.  Wybierz odpowiednią platformę docelową (zazwyczaj `Windows 64-bit`).
3.  Skompiluj projekt (Build). Wynikiem będzie plik `DriveSize.cpl` (lub `.dll` ze zmienionym rozszerzeniem).

### 2. Instalacja Ręczna (Kopiowanie)

Najprostszą metodą instalacji jest skopiowanie pliku `.cpl` do katalogu systemowego:

- Dla systemów 64-bitowych i kompilacji 64-bit: skopiuj do `C:\Windows\System32`.
- Dla systemów 64-bitowych i kompilacji 32-bit: skopiuj do `C:\Windows\SysWOW64`.

Po skopiowaniu, aplet powinien automatycznie pojawić się w Panelu Sterowania (widok "Duże ikony" lub "Małe ikony").

### 3. Rejestracja w Rejestrze (Zalecane)

Aby mieć pewność, że system Windows poprawnie wykryje aplet (szczególnie w nowszych wersjach), warto dodać wpis do rejestru.

Uruchom wiersz poleceń (CMD) jako Administrator i wpisz:

```cmd
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cpls" /v DriveSize /t REG_SZ /d "C:\Ścieżka\Do\Pliku\DriveSize.cpl" /f
```

_(Zastąp `C:\Ścieżka\Do\Pliku\...` rzeczywistą ścieżką do pliku .cpl)_

### 4. Uruchomienie

Po instalacji, aplet można uruchomić na kilka sposobów:

1.  **Panel Sterowania**: Otwórz Panel Sterowania (widok klasyczny) i kliknij ikonę "Drive Size".
2.  **Polecenie Uruchom**: Wciśnij `Win + R` i wpisz:
    ```cmd
    control.exe DriveSize.cpl
    ```
    (jeśli plik jest w ścieżce systemowej lub podasz pełną ścieżkę).
3.  **Bezpośrednio**: Dwukrotne kliknięcie na plik `.cpl` (jeśli skojarzenia plików są standardowe).

## Rozwiązywanie Problemów

- **Brak apletu w Panelu Sterowania**: Upewnij się, że architektura pliku (32/64 bit) zgadza się z katalogiem systemowym (`System32` dla 64-bit, `SysWOW64` dla 32-bit na systemie 64-bit).
- **"Brak odpowiedzi" podczas skanowania**: Aplet jest zoptymalizowany, ale przy bardzo dużej liczbie małych plików (np. miliony plików w `Windows\Installer`) skanowanie może trwać dłużej. Pasek postępu informuje o statusie.

---

# DriveSize - Disk Space Analyzer (Control Panel Applet)

## Project Description

DriveSize is a Windows Control Panel applet (`.cpl` file) designed to scan all local hard drives and present the scan results in the form of an interactive pie chart with a detailed legend.

The applet allows the user to quickly identify which folders occupy the most disk space without the need to install heavy external tools.

## Key Features

- **Automatic Scanning**: Detects and scans all fixed drive partitions in the system.
- **Data Visualization**: Presents disk usage on a pie chart divided into:
  - **Top 3 Folders**: The three largest directories in the root of the drive.
  - **Other**: Remaining used space.
  - **Free**: Available space.
- **Interactive Legend**:
  - Each chart segment has a "bubble" label with a description (name, percentage, size in GB).
  - **Bi-directional Highlighting**: Hovering over a chart slice highlights the corresponding label and leader line (in orange-red). Similarly, hovering over a label highlights the corresponding slice on the chart.
- **Performance**: Scanning runs in the background with mechanisms to prevent UI freezing (refresh throttling, asynchronous updates).

## System Requirements

- Operating System: Windows 7, 8, 10, 11 (x86 or x64).
- Administrator Privileges (for installation in system directories or registry registration).

## Installation and Deployment Guide

### 1. Compilation

The project is written in the Delphi environment. To build the output file:

1.  Open the `DriveSize.dpr` project file in the Delphi IDE.
2.  Select the appropriate target platform (usually `Windows 64-bit`).
3.  Compile the project (Build). The result will be a `DriveSize.cpl` file (or a `.dll` with a renamed extension).

### 2. Manual Installation (Copying)

The simplest installation method is copying the `.cpl` file to the system directory:

- For 64-bit systems and 64-bit compilation: copy to `C:\Windows\System32`.
- For 64-bit systems and 32-bit compilation: copy to `C:\Windows\SysWOW64`.

After copying, the applet should automatically appear in the Control Panel ("Large icons" or "Small icons" view).

### 3. Registry Registration (Recommended)

To ensure Windows correctly detects the applet (especially in newer versions), it is recommended to add a registry entry.

Run Command Prompt (CMD) as Administrator and type:

```cmd
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cpls" /v DriveSize /t REG_SZ /d "C:\Path\To\File\DriveSize.cpl" /f
```

_(Replace `C:\Path\To\File\...` with the actual path to the .cpl file)_

### 4. Running

After installation, the applet can be launched in several ways:

1.  **Control Panel**: Open Control Panel (classic view) and click the "Drive Size" icon.
2.  **Run Command**: Press `Win + R` and type:
    ```cmd
    control.exe DriveSize.cpl
    ```
    (if the file is in the system path or you provide the full path).
3.  **Directly**: Double-click the `.cpl` file (if file associations are standard).

## Troubleshooting

- **Applet missing from Control Panel**: Ensure the file architecture (32/64 bit) matches the system directory (`System32` for 64-bit, `SysWOW64` for 32-bit on a 64-bit system).
- **"Not Responding" during scan**: The applet is optimized, but with a very large number of small files (e.g., millions of files in `Windows\Installer`), scanning may take longer. The progress bar indicates status.
