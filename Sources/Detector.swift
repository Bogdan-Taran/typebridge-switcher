import Foundation

enum Language: String { case en, ru
    var other: Language { self == .en ? .ru : .en }
}

enum Sensitivity: Int { case careful, balanced, fast
    var minimum: Int { self == .fast ? 2 : 3 }
}

struct KeyboardMap {
    var forward: [Character: Character]
    var backward: [Character: Character]

    init(pairs: [(Character, Character)] = Array(zip(
        "`qwertyuiop[]asdfghjkl;'zxcvbnm,.",
        "ёйцукенгшщзхъфывапролджэячсмитьбю"))) {
        forward = [:]; backward = [:]
        for (en, ru) in pairs where en != ru {
            forward[en] = ru; backward[ru] = en
            if let e = String(en).uppercased().first, let r = String(ru).uppercased().first,
               en.isLetter, ru.isLetter { forward[e] = r; backward[r] = e }
        }
    }

    func convert(_ text: String, from language: Language) -> String? {
        let map = language == .en ? forward : backward
        var result = ""
        for char in text {
            guard let mapped = map[char] else { return nil }
            result.append(mapped)
        }
        return result
    }
}

final class Detector {
    var map = KeyboardMap()
    var sensitivity: Sensitivity = .balanced
    var exceptions: Set<String> = []
    var customWords: Set<String> = [] { didSet { rebuild() } }
    var spelling: ((String, Language) -> Bool)?
    private var words: [Language: Set<String>] = [:]
    private var prefixes: [Language: Set<String>] = [:]

    init() { rebuild() }

    private func rebuild() {
        for language in [Language.en, .ru] {
            let base = language == .en ? Self.english : Self.russian
            var set = Set(base.split(whereSeparator: { $0.isWhitespace }).map(String.init))
            set.formUnion(customWords.filter { Self.language(of: $0) == language })
            words[language] = set
            prefixes[language] = Set(set.flatMap { word in
                (1...word.count).map { String(word.prefix($0)) }
            })
        }
    }

    static func language(of text: String) -> Language? {
        if text.unicodeScalars.contains(where: { (0x0400...0x04ff).contains($0.value) }) { return .ru }
        if text.contains(where: { $0.isASCII && $0.isLetter }) { return .en }
        return nil
    }

    func correction(_ original: String, from language: Language, boundary: Bool) -> String? {
        let raw = original.lowercased()
        guard raw.count >= (boundary ? 3 : sensitivity.minimum), raw.count <= 48,
              !exceptions.contains(raw),
              let converted = map.convert(original, from: language),
              converted.allSatisfy({ $0.isLetter }), Self.language(of: converted) == language.other,
              !exceptions.contains(converted.lowercased()) else { return nil }
        let target = converted.lowercased()
        // A valid word in the current language always wins over a guess.
        guard words[language]?.contains(raw) != true else { return nil }
        if boundary {
            guard spelling?(raw, language) != true else { return nil }
            return (words[language.other]?.contains(target) == true || spelling?(target, language.other) == true)
                ? converted : nil
        }
        guard sensitivity != .careful,
              prefixes[language]?.contains(raw) != true,
              prefixes[language.other]?.contains(target) == true else { return nil }
        guard original != original.uppercased() else { return nil }
        if raw.count == 2 {
            // Deliberately tiny list: arbitrary two-letter fragments are ambiguous.
            let distinctive: Set<String> = language == .en ? ["gh", "jr", "xt", "zv"] : ["руд", "щз", "цк"]
            return distinctive.contains(raw) ? converted : nil
        }
        // Do not rewrite acronyms and all-caps identifiers automatically.
        let vowels = language == .en ? Set("aeiouy") : Set("аеёиоуыэюя")
        let noVowels = !raw.contains(where: { vowels.contains($0) })
        let unusual: Set<String> = language == .en
            ? ["gh", "hb", "bd", "dt", "tn", "pf", "df", "yj", "rj", "cr", "xt", "jn", "lf", "cn", "gj", "ds", ";b", "kj", "uj"]
            : ["щз", "цк", "дд", "щк", "ут", "фк", "уы", "шщ", "щц", "ук", "нщ", "щг"]
        let pairs = zip(raw, raw.dropFirst()).map { String([$0.0, $0.1]) }
        let evidence = noVowels || pairs.contains(where: unusual.contains)
        return (sensitivity == .fast || evidence || raw.count >= 5) ? converted : nil
    }

    private static let english = """
    a about above accept access account across action active actually add address after again against age ago agree air all allow almost alone along already also although always am among amount an and another answer any anyone anything anyway app apple application apply are area around arrive art as ask at away awesome baby back bad balance bank base basic be beautiful because become bed been before begin behind believe below best better between big bill bit black blue board body book both box boy break bring browser build business but buy by call came can cannot car care case cat cause change chat check child children choice choose city class clean clear close code coffee cold color come common company computer consider contact continue control copy could country course create current cut daily dark data date day dead deal dear decide deep default design desktop detail develop did difference different difficult do does dog doing done door down download draw dream drive during each early earth easy eat education effect either else email end enjoy enough enter error especially even evening event ever every everybody everyone everything example expect experience explain eye face fact fail fall family far fast father favorite feel few field file fill final finally find fine finish fire first five fix floor focus follow food for force form forward found four free friend from front full fun function future game gave general get girl give given go goal god goes going good got great green group grow guess guy had half hand happen happy hard has have having he head hear heard heart hello help her here hey hi high him himself his history home hope hot hour house how however human i idea if image important improve in include information input inside install instead interest into is issue it its itself job join just keep key kind know language large last late later launch law lead learn least leave left less let letter level life light like line link list little live local long look lot love low made main make man many map market matter may maybe me mean means meet member men menu message might mind minute miss mobile mode model moment money month more morning most mother move much music must my myself name nation natural near need never new news next nice night no nobody node none nor normal not note nothing now number of off offer office often oh old on once one only open option or order other our out outside over own page paper parent part party pass past pause pay people per perfect perhaps person phone photo pick picture place plan play please point poor position possible power prefer present pretty price problem process program project public put quality question quick quite read ready real really reason receive record red remember remove reply require rest result return review right room rule run said same save saw say school screen search second see seem seen select send sense sent separate server service set setting seven several shall she shift short should show side simple since single sit site six size sleep small so social some somebody someone something sometimes son soon sorry sort sound source space speak special start state stay step still stop story strong student study stuff such support sure switch system table take talk task team tell test text than thank thanks that the their them themselves then there these they thing think third this those though thought three through time to today together told tomorrow too took tool top total touch toward town tree true try turn two type under understand until up update upon us use used user using usual value version very video view visit voice wait walk want war warm was watch water way we web website week well went were what whatever when where whether which while white who whole why wide will win window wish with within without woman women word work world would write wrong year yes yet you young your yourself
    hello help hello world welcome keyboard english russian programming swift python javascript github google safari chrome terminal mac macbook macos linux windows function return const string print import export async await public private class enum struct protocol test debug build commit branch merge pull push request response status token settings password email online offline internet network website https http www com org net localhost admin api url json html css sql git npm node docker kubernetes xcode codex openai chatgpt
    """

    private static let russian = """
    а адрес аккаунт акция английский автоматически автор большой больше будет будто будем будешь буду быть бы был была были было быстро важный вам вас ваш ваша ваши ведь весь вещи вечер видеть вид время вместе вместо внутри внимание вода возможно вопрос вот вообще всем всего все всегда всё выйти выход где главный глаза год года город готов готово говорить говорил голова да даже дальше данная данные дата два две дверь день денег деньги дети дело дела делать десять действительно для до добрый доброе доброго должен должна дом дома дорога друг друзья думать думаю его её еще ещё если есть ему эта этот эти это этого этом жизнь за зачем здравствуйте здесь земля знать знаю значит значение задача закрыть запуск зачем иногда из или им именно имя интернет их как какая какой какие кажется каждый карта когда конечно конец компьютер код команда который которая которые кто куда люди лучше любой люблю маленький мало мама меня между место месяц мне много можно мой моя мои может можем можешь можете машина меню мир минута минут мы на надо назад найти нам нас наш наша наши начать настройки него неделя неё нельзя несколько нет ничего новый новая новости но нужно нужен нужна нужный номер ноутбук о об оба однако один одна одном окно он она они оно опять очень от ответ открыть отлично ошибка память папка первый перед переключить перевод письмо писать по пока показать после последний потом потому почему пожалуйста привет приветик приветствие пример приложение программа просто проблема пробел продолжить проект проверить работает работа работать раз разве разве размер раскладка русский раньше рассказать сразу свой сегодня сейчас себе себя сделать секунд сердце система сказать сколько словно слово слова случай смотреть снова со спасибо способ стоит сторона строка стол столько стать статья стоит сюда так также такая такой там тебя тебе теперь тем тема терминал текст телефон то тогда тоже только том тот три тут ты у уже узнать убрать увидеть удобный указать установить утро файл функция хорошо хотя хочу цвет цель час часть часто человек чего чем через читать что чтобы чуть экран это я язык являюсь январь февраль март апрель май июнь июль август сентябрь октябрь ноябрь декабрь понедельник вторник среда четверг пятница суббота воскресенье
    привет приветствую приветствие привыкнуть привычка причина принято принимать прийти приятно приложение приложения прикрепить пример примерный прекрасно предыдущий предложение продолжать проверить проверка просто пространство прошлый профессия процесс программа программирование продукт продолжение проект происходить получить полное помощь помоги помогите понятно понимаю пожалуйста почему посмотреть поставить пользоваться пользователь поделиться подписать подключить подождать подготовить подходит поддержка спасибо спросить скачать сколько скажи сказать сказать сегодня сейчас следующая следующий сообщение сообщение сообщить событие совсем согласен сохранить сохранение открыть отправить ответить отправка обязательно обновить обновление обычно ошибка обратно отключить доступ добро доброе добрый доброго документ документы добавить добавление достаточно действительно делать давай давайте данные давно другой друзья женщина мужчина ребёнок ребёнка ребёнку хороший хорошая хорошего хорошо хочется хочу хочешь время времени временно включить выключить вложение внимание возможность возможно вопросы вопрос встреча вместе вчера завтра запись записать записаться задача задачи зачем здесь здравствуйте здравствуй интересный информация интересно искать инструкция исправить использовать история качество картинка кабинет клиент кнопка конечно контакт конец короткий количество купить любовь личный лучше любимый место можно можно моя музыка начать начнём настройки настройки настроить нажать находится написать напиши направление например необходимо несколько недоступно ничего новое обновление окно оставить особенности основной оценка очень пароль память папка письмо письма писать подключение поддержка поздно потом помощь понять правда правильно правильный правила приложение приложения работа рабочий работает работаю работаем рабочая результат решение решить режим русский российский сегодня сделать сейчас синий случай случайно снова смотреть смотри собственный совсем сначала ссылка создать сообщить состояние список способ спасибо статус страница столько текст текущий также тестирование точка только третий требовать трудный уведомление удалить уже узнать удобно удачно установить устройство учёт файл файлы фотография функция хорошо цвет цифровой читать школа экран язык языки
    """
}
