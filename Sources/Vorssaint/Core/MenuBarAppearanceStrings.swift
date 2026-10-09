// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarAppearanceStrings {
    let label: String
    let values: String
    let bars: String
    let caption: String
    let customize: String
    let normalColor: String
    let mediumColor: String
    let highColor: String
    let mediumFrom: String
    let highFrom: String
    let replaceIconToggle: String
    let replaceIconCaption: String
    let temperatureLayout: String
    let topSensor: String
    let bottomSensor: String
    let stacked: String
    let sideBySide: String
}

extension FeatureStrings {
    static func menuBarAppearance(_ language: AppLanguage) -> MenuBarAppearanceStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension MenuBarAppearanceStrings {
    static let enUS = MenuBarAppearanceStrings(
        label: "Usage display",
        values: "Values",
        bars: "Bars",
        caption: "Bars apply to CPU, GPU, memory and disk usage. Other readings stay numeric.",
        customize: "Bar colors and limits",
        normalColor: "Normal color",
        mediumColor: "Medium color",
        highColor: "High color",
        mediumFrom: "Medium from",
        highFrom: "High from",
        replaceIconToggle: "Replace menu bar icon with temperatures",
        replaceIconCaption: "Displays live temperature readouts directly on the main menu bar icon",
        temperatureLayout: "Temperature layout",
        topSensor: "Top sensor",
        bottomSensor: "Bottom sensor",
        stacked: "Stacked",
        sideBySide: "Side by side"
    )

    static let ptBR = MenuBarAppearanceStrings(
        label: "Exibição de uso",
        values: "Valores",
        bars: "Barras",
        caption: "As barras mostram o uso de CPU, GPU, memória e disco. As outras leituras continuam numéricas.",
        customize: "Cores e limites das barras",
        normalColor: "Cor normal",
        mediumColor: "Cor média",
        highColor: "Cor alta",
        mediumFrom: "Médio a partir de",
        highFrom: "Alto a partir de",
        replaceIconToggle: "Substituir ícone da barra de menus por temperaturas",
        replaceIconCaption: "Exibe leituras de temperatura em tempo real no ícone principal",
        temperatureLayout: "Layout de temperatura",
        topSensor: "Sensor superior",
        bottomSensor: "Sensor inferior",
        stacked: "Empilhado",
        sideBySide: "Lado a lado"
    )

    static let tr = MenuBarAppearanceStrings(
        label: "Kullanım görünümü",
        values: "Değerler",
        bars: "Çubuklar",
        caption: "Çubuklar CPU, GPU, bellek ve disk kullanımını gösterir. Diğer ölçümler sayısal kalır.",
        customize: "Çubuk renkleri ve sınırları",
        normalColor: "Normal renk",
        mediumColor: "Orta renk",
        highColor: "Yüksek renk",
        mediumFrom: "Orta başlangıcı",
        highFrom: "Yüksek başlangıcı",
        replaceIconToggle: "Menü çubuğu simgesini sıcaklıklarla değiştir",
        replaceIconCaption: "Ana menü çubuğu simgesinde canlı sıcaklık değerlerini gösterir",
        temperatureLayout: "Sıcaklık düzeni",
        topSensor: "Üst sensör",
        bottomSensor: "Alt sensör",
        stacked: "Üst üste",
        sideBySide: "Yan yana"
    )

    static let ru = MenuBarAppearanceStrings(
        label: "Отображение нагрузки",
        values: "Значения",
        bars: "Шкалы",
        caption: "Шкалы показывают загрузку CPU, GPU, памяти и диска. Остальные показатели остаются числовыми.",
        customize: "Цвета и пороги шкал",
        normalColor: "Обычный цвет",
        mediumColor: "Средний цвет",
        highColor: "Высокий цвет",
        mediumFrom: "Средний от",
        highFrom: "Высокий от",
        replaceIconToggle: "Заменить иконку строки меню температурой",
        replaceIconCaption: "Отображает текущую температуру прямо на главной иконке строки меню",
        temperatureLayout: "Расположение температур",
        topSensor: "Верхний датчик",
        bottomSensor: "Нижний датчик",
        stacked: "Столбцом",
        sideBySide: "Рядом"
    )

    static let es = MenuBarAppearanceStrings(
        label: "Vista de uso",
        values: "Valores",
        bars: "Barras",
        caption: "Las barras muestran el uso de CPU, GPU, memoria y disco. Las demás lecturas siguen siendo numéricas.",
        customize: "Colores y límites de las barras",
        normalColor: "Color normal",
        mediumColor: "Color medio",
        highColor: "Color alto",
        mediumFrom: "Medio desde",
        highFrom: "Alto desde",
        replaceIconToggle: "Reemplazar icono de la barra de menús por temperaturas",
        replaceIconCaption: "Muestra temperaturas en tiempo real en el icono principal de la barra de menús",
        temperatureLayout: "Diseño de temperatura",
        topSensor: "Sensor superior",
        bottomSensor: "Sensor inferior",
        stacked: "Apilado",
        sideBySide: "Lado a lado"
    )

    static let sk = MenuBarAppearanceStrings(
        label: "Zobrazenie vyťaženia",
        values: "Hodnoty",
        bars: "Pruhy",
        caption: "Pruhy platia pre vyťaženie CPU, GPU, pamäte a disku. Ostatné hodnoty zostávajú číselné.",
        customize: "Farby a limity pruhov",
        normalColor: "Bežná farba",
        mediumColor: "Stredná farba",
        highColor: "Vysoká farba",
        mediumFrom: "Stredná od",
        highFrom: "Vysoká od",
        replaceIconToggle: "Nahradiť ikonu v lište teplota mi",
        replaceIconCaption: "Zobrazuje živé hodnoty teplôt priamo v hlavnej ikone lišty",
        temperatureLayout: "Rozloženie teplôt",
        topSensor: "Horný snímač",
        bottomSensor: "Dolný snímač",
        stacked: "Nad sebou",
        sideBySide: "Vedľa seba"
    )

    static let de = MenuBarAppearanceStrings(
        label: "Auslastungsanzeige",
        values: "Werte",
        bars: "Balken",
        caption: "Balken zeigen die Auslastung von CPU, GPU, Speicher und Festplatte. Andere Messwerte bleiben numerisch.",
        customize: "Balkenfarben und Grenzwerte",
        normalColor: "Normale Farbe",
        mediumColor: "Mittlere Farbe",
        highColor: "Hohe Farbe",
        mediumFrom: "Mittel ab",
        highFrom: "Hoch ab",
        replaceIconToggle: "Menüleistensymbol durch Temperaturen ersetzen",
        replaceIconCaption: "Zeigt Live-Temperaturen direkt auf dem Hauptsymbol der Menüleiste an",
        temperatureLayout: "Temperatur-Layout",
        topSensor: "Oberer Sensor",
        bottomSensor: "Unterer Sensor",
        stacked: "Gestapelt",
        sideBySide: "Nebeneinander"
    )

    static let fr = MenuBarAppearanceStrings(
        label: "Affichage de l’utilisation",
        values: "Valeurs",
        bars: "Barres",
        caption: "Les barres indiquent l’utilisation du CPU, du GPU, de la mémoire et du disque. Les autres mesures restent numériques.",
        customize: "Couleurs et seuils des barres",
        normalColor: "Couleur normale",
        mediumColor: "Couleur moyenne",
        highColor: "Couleur élevée",
        mediumFrom: "Moyen à partir de",
        highFrom: "Élevé à partir de",
        replaceIconToggle: "Remplacer l’icône de la barre des menus par les températures",
        replaceIconCaption: "Affiche en direct les températures sur l’icône principale de la barre des menus",
        temperatureLayout: "Disposition des températures",
        topSensor: "Capteur supérieur",
        bottomSensor: "Capteur inférieur",
        stacked: "Superposé",
        sideBySide: "Côte à côte"
    )

    static let it = MenuBarAppearanceStrings(
        label: "Visualizzazione utilizzo",
        values: "Valori",
        bars: "Barre",
        caption: "Le barre mostrano l’utilizzo di CPU, GPU, memoria e disco. Le altre letture restano numeriche.",
        customize: "Colori e soglie delle barre",
        normalColor: "Colore normale",
        mediumColor: "Colore medio",
        highColor: "Colore alto",
        mediumFrom: "Medio da",
        highFrom: "Alto da",
        replaceIconToggle: "Sostituisci l'icona della barra dei menu con le temperature",
        replaceIconCaption: "Mostra le letture delle temperature in tempo reale sull'icona principale",
        temperatureLayout: "Layout temperature",
        topSensor: "Sensore superiore",
        bottomSensor: "Sensore inferiore",
        stacked: "Impilato",
        sideBySide: "A fianco"
    )

    static let ja = MenuBarAppearanceStrings(
        label: "使用率の表示",
        values: "数値",
        bars: "バー",
        caption: "CPU、GPU、メモリ、ディスクの使用率をバーで表示します。その他の測定値は数値のままです。",
        customize: "バーの色としきい値",
        normalColor: "通常の色",
        mediumColor: "中程度の色",
        highColor: "高負荷の色",
        mediumFrom: "中程度の開始",
        highFrom: "高負荷の開始",
        replaceIconToggle: "メニューバーアイコンを温度表示に置き換える",
        replaceIconCaption: "メインのメニューバーアイコンにリアルタイムの温度を表示します",
        temperatureLayout: "温度のレイアウト",
        topSensor: "上のセンサー",
        bottomSensor: "下のセンサー",
        stacked: "上下に配置",
        sideBySide: "左右に配置"
    )

    static let ko = MenuBarAppearanceStrings(
        label: "사용량 표시",
        values: "값",
        bars: "막대",
        caption: "CPU, GPU, 메모리 및 디스크 사용량을 막대로 표시합니다. 다른 측정값은 숫자로 유지됩니다.",
        customize: "막대 색상 및 기준",
        normalColor: "보통 색상",
        mediumColor: "중간 색상",
        highColor: "높음 색상",
        mediumFrom: "중간 시작",
        highFrom: "높음 시작",
        replaceIconToggle: "메뉴 막대 아이콘을 온도 표시로 교체",
        replaceIconCaption: "기본 메뉴 막대 아이콘에 실시간 온도 측정값을 표시합니다",
        temperatureLayout: "온도 레이아웃",
        topSensor: "상단 센서",
        bottomSensor: "하단 센서",
        stacked: "수직 배치",
        sideBySide: "수평 배치"
    )

    static let zhHans = MenuBarAppearanceStrings(
        label: "使用率显示",
        values: "数值",
        bars: "条形",
        caption: "CPU、GPU、内存和磁盘使用率以条形显示。其他读数保持数字显示。",
        customize: "条形颜色和阈值",
        normalColor: "正常颜色",
        mediumColor: "中等颜色",
        highColor: "高负载颜色",
        mediumFrom: "中等起点",
        highFrom: "高负载起点",
        replaceIconToggle: "用温度替换菜单栏图标",
        replaceIconCaption: "在主菜单栏图标上直接显示实时温度读数",
        temperatureLayout: "温度布局",
        topSensor: "顶部传感器",
        bottomSensor: "底部传感器",
        stacked: "上下堆叠",
        sideBySide: "左右并排"
    )

    static let zhTW = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        caption: "CPU、GPU、記憶體和磁碟使用率以長條顯示。其他讀數維持數字顯示。",
        customize: "長條顏色和門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點",
        replaceIconToggle: "以溫度取代選單列圖示",
        replaceIconCaption: "在主選單列圖示上直接顯示即時溫度讀數",
        temperatureLayout: "溫度版面配置",
        topSensor: "頂部感測器",
        bottomSensor: "底部感測器",
        stacked: "上下堆疊",
        sideBySide: "左右並排"
    )

    static let zhHK = MenuBarAppearanceStrings(
        label: "使用率顯示",
        values: "數值",
        bars: "長條",
        caption: "CPU、GPU、記憶體及磁碟使用率以長條顯示。其他讀數維持數字顯示。",
        customize: "長條顏色及門檻",
        normalColor: "正常顏色",
        mediumColor: "中等顏色",
        highColor: "高負載顏色",
        mediumFrom: "中等起點",
        highFrom: "高負載起點",
        replaceIconToggle: "以溫度取代選單列圖示",
        replaceIconCaption: "在主選單列圖示上直接顯示即時溫度讀數",
        temperatureLayout: "溫度版面配置",
        topSensor: "頂部感應器",
        bottomSensor: "底部感應器",
        stacked: "上下堆疊",
        sideBySide: "左右並排"
    )
    static let uk = MenuBarAppearanceStrings(
        label: "Відображення використання",
        values: "Значення",
        bars: "Смуги",
        caption: "Смуги застосовуються до використання CPU, GPU, пам’яті та диска. Інші показники залишаються числовими.",
        customize: "Кольори та ліміти смуг",
        normalColor: "Звичайний колір",
        mediumColor: "Середній колір",
        highColor: "Високий колір",
        mediumFrom: "Середній від",
        highFrom: "Високий від",
        replaceIconToggle: "Замінити іконку в смузі меню температурою",
        replaceIconCaption: "Відображає температуру в реальному часі безпосередньо на головній іконці",
        temperatureLayout: "Макет температури",
        topSensor: "Верхній датчик",
        bottomSensor: "Нижній датчик",
        stacked: "Стовпчиком",
        sideBySide: "Поруч"
    )
}
