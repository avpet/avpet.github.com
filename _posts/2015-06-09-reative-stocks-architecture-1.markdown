---
layout: post
title:  "Reactive Push, Composition и UI на примере Reactive Stocks - 1"
date:   2015-06-09 05:30:00
categories: scala
image: http://i.imgur.com/yHXn1A6.png
reactive-stock-src: https://github.com/typesafehub/reactive-stocks/blob/master/
---

<style>
/* To center images */
.center {
    text-align: center;
}
</style>

*Реактивное программирование* — парадигма программирования, ориентированная на потоках данных и распространении изменений. 

Реактивное приложение - приложение, характеризующееся следующими свойствами: 

* ориентированность на события

* масштабируемость (способность к увеличению производительности при добавлении ресурсов) 

* отказоустойчивость и отзывчивость (малое время отклика) 

* способность работать в реальном времени (наличие гарантированного время отклика, не зависящее от нагрузки). 

Приложения, использующие асинхронную модель, характеризуются также слабой связанностью - отправитель и получатель могут быть реализованы без оглядки на детали, как именно события распространяются в системе, и реализация больше фокусируется на содержимом передачи, т.е. на контракте сообщений.

Дополнительным преимуществом асинхронной модели, т.е. основанной на передаче сообщений, а не синхронных вызовах, является то, что вызывающий поток не блокируется, как при модели синхронных вызовов, а продолжает выполнение. Неблокирующее приложение обладает меньшими задержками и большей пропускной способностью по сравнению с приложением, основанном на блокирующей синхронизации - поскольку мы более эффективно используем ресурсы процессора.

Корнем слова "реактивный" является слово "react", т.е. реагировать, отзываться, т.е. можно говорить, что реактивные приложения:

* реагируют на события — событийно-ориентированные;

* реагируют на загрузку — масштабируемые;

* реагируют на отказы — отказоустойчивые.

Когда говорят, что запросы являются реактивными, имеют в виду, что они являются асинхронными, т.е. неблокирующими.

Приложение [*Reactive Stocks*](http://www.typesafe.com/activator/template/reactive-stocks) демонстрирует 4 аспекта реактивного программирования: реактивный push, реактивные запросы, композицию реактивных запросов, и реактивный интерфейс. 

Исходники можно также просмотреть [тут](https://github.com/typesafehub/reactive-stocks).

В нем не показана реактивная pull - модель, при которой клиент периодически запрашивает данные, ожидая их появления, с помощью реактивных запросов; в отличие от push-модели, при pull-модели запрос инициируется клиентом.

В случае реактивного push-запроса сервер "проталкивает" данные к своим потребителям незамедлительно после того, когда данные становятся доступны, вместо того, чтобы заставлять клиента впустую тратить ресурсы, постоянно запрашивая и ожидая данные.
 
*push* лучше чем *pull*, поскольку мы не делаем лишних запросов с клиента - но это при условии, что клиент достаточно быстро обрабатывает *push* запросы с сервера и при условии, что и сервер, и клиент поддерживают такой тип взаимодействия (например, с помощью *WebSocket*).

*Реактивная композиция* - комбинирование асинхронных неблокирующих запросов; например, у нас есть запрос к вызову, реализованному асинхронным Play-контроллером, и этот вызов, асинхронный по своей природе, приводит к двум дополнительным параллельным асинхронным вызовам к двум разным веб сервисам, результат которых нужно объединить и вернуть клиенту. 

Существует еще одна модель - 2-сторонняя реактивность - что на самом деле означает двусторонний реактивный push.

Вообще, в последние годы возник ряд технологий, поддерживающих создание реактивных приложений ([Microsoft Reactive extensions](https://msdn.microsoft.com/en-us/data/gg577609.aspx), [Ractive.js](http://www.ractivejs.org/) и др.).

Среди прочего, одной из основных причин, по которым создание реактивных приложений стало востребованным, можно назвать повышение требований к отзывчивости HTML5 интерфейсов, а также также значительный рост числа запросов к веб-приложениям и сервисам. К тому же, например, у мобильных устройств несколько ограничены возможности для pull-запросов, соответственно push-модель, основанная на WebSocket'ах, является для них более подходящей.

Ну или пример из еще один жизни реактивных интерфейсов - одновременные изменения в issue на github видны одновременно всем пользователям без перезагрузки страницы. 

И еще пару слов о том, что, возможно, покажется малосвязанным напрямую с реактивным программированием, но косвенно с ним связано - развертывание, или деплоймент, и мониторинг. Деплоймент, при котором  время даунтайма стремится к нулю, и мониторинг, который позволяет не допустить снижения отзывчивости или вообще отказа системы, являются довольно важными вещами для обеспечения "реактивности" приложения.

Например, беcконтейнерный деплоймент (а именно так может работать Play-приложение, т.е. безо всякого контейнера), потому что он неплохо ложится в парадигму непрерывного развертывания [continuous delivery](http://en.wikipedia.org/wiki/Continuous_delivery), т.е. для развертывания часто достаточно простого копирования, вместо манипуляций со сложной инфраструктурой серверов приложений. 

Некоторые дополнительные приемы, призванные снизить время неработоспособности приложения:

* ["Canary deployments"](http://martinfowler.com/bliki/CanaryRelease.html) 
* ["Rolling updates"](http://aws.amazon.com/about-aws/whats-new/2013/11/11/aws-elastic-beanstalk-announces-rolling-updates/)
* ["Различные приемы для миграции схемы БД в условиях непрерывного развертывания"](http://www.grahambrooks.com/continuous%20delivery/continuous%20deployment/zero%20down-time/2013/08/29/zero-down-time-relational-databases.html)

В качестве инструмента мониторинга может быть использована [Typesafe Console](http://resources.typesafe.com/docs/console/manual/overview.html) - которая мониторит события в реактивном приложении, написанном с использованием Play и Akka. Также,  мониторинг для приложений, написанных  с использованием Scala/Akka/Play, поддерживается в [New Relic - с использованием специального агента](https://docs.newrelic.com/docs/agents/java-agent/installation/java-agent-manual-installation). Рожжерживается он в [Takipi](http://www.typesafe.com/blog/Introducing-Takipi-God-Mode-in-Production-Scala-Code) и [AppDynamics](https://blog.appdynamics.com/java/appdynamics-pro-supports-scala-and-the-typesafe-reactive-platform-with-play2akka/)

#### [Reactive Stocks](https://github.com/typesafehub/reactive-stocks) ####

Итак, приложение [*Reactive Stocks*](http://www.typesafe.com/activator/template/reactive-stocks). На самом деле приложение *Reactive Stocks* является [шаблоном в Typesafe Activator](https://www.typesafe.com/activator/templates), но при этом не является совсем уже примитивным.

{: .center}
![KXWxs2u.png](http://i.imgur.com/KXWxs2u.png)

Приложение *Reactive Stocks* написано на Scala и Java с использованием Play и Akka с целью показать на сравнительно простом примере реактивный подход. В частности, *Reactive Composition* и *Reactive Push*.

Идея приложения довольно проста  - на каждой открытой странице оно показывает набор графиков котировок, которые "проталкиваются" от сервера в клиент с помощью WebSocket. В данном случае значения фейковые, генерируемые случайным образом. *Reactive Stocks* написано с использованием *Play* и *Akka*,  причем бэкенд частично написан на Java, а не только на Scala -  с целью показать, насколько оба языка просто сосуществуют в рамках одного приложения. Фронтенд использует [CoffeeScript](http://coffeescript.org/) в качестве клиентского языка, и [WebSockets](https://developer.mozilla.org/en/docs/WebSockets) в для push-запросов.

В *Reactive Stocks* используются четыре вида "реактивности": реактивный push, реактивные запросы, реактивная композиция, и реактивный UI. Ни реактивный pull, ни 2-сторонняя реактивность в *Reactive Stocks* не используются, хотя в реальном приложении, которое бы показывало котировки и использовало бы реальный источник биржевых котировок (а не генерирующий последовательность случайных значений), скорее всего, использовался бы реактивный pull - поскольку большинство веб сервисов котировок реализовано как REST или SOAP веб-сервисы, и не используют WebSockets. 

Реактивный *push*
Приложение использует *WebSocket*, для того чтобы "втолкнуть" данные о котировках в клиента, т.е. браузер. Для создания соединения `WebSocket` в  Play, сперва должен быть определен маршрут (*route*) в файле [`conf/routes`]({{page.reactive-stock-src}}conf/routes), а именно:

`GET /ws controllers.Application.ws`

Метод `ws` в контроллере [`Application.java`]({{page.reactive-stock-src}}app/controllers/Application.java) создает объект [`WebSocket`]({{page.reactive-stock-src}}app/controllers/Application.java#L25), принимающий запросы на отслеживание котировок и отсылающий значения котировок обратно;  `WebSocket` также создаст [`UserActor`]({{page.reactive-stock-src}}app/actors/UserActor.java) (на каждую сессию с пользователем, фактически страницу, создается свой `WebSocket`, а следовательно - `UserActor`) и передаст в него ссылку на *out*-канал `WebSocket` для обратной связи. 

После того, как `UserActor` создан, набор котировок по умолчанию (который определяется параметром `default.stocks` в файле конфигурации [`application.conf`]({{page.reactive-stock-src}}conf/application.conf)) добавляется в список отслеживаемых для данной сессии котировок. 

Каждая котировка (обозначаемая уникальным символом - например, `GOOG` или `ORCL`) соответствует одному [`StockActor`у]({{page.reactive-stock-src}}app/actors/StockActor.scala). [`StockActor`]({{page.reactive-stock-src}}app/actors/StockActor.scala) держит последние 50 значений цен котировки. В ответ на сообщение [`FetchLatest`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L74) можно получить всю историю цен. В ответ на сообщение [`FetchLatest`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L74) будет получена новая цена путем вызова метода [`newPrice`]({{page.reactive-stock-src}}app/utils/StockQuote.java#L4) в [`StockQuote`]({{page.reactive-stock-src}}app/utils/StockQuote.java) - источнике цен. Каждый `StockActor` отсылает сообщение [`FetchLatest`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L30) самому себе каждые 75 миллисекунд. Как только получено новое значение цены, оно добавляется в [историю цен]({{page.reactive-stock-src}}app/actors/StockActor.scala#L24) (фактически очередь значений, `Queue`) и оно же рассылается всем подписчикам, то есть всем `UserActor`ам, которые отслеживают котировки. `UserActor` сериализует сообщение о ценах в JSON  и "проталкивает" это сообщение в клиента с помощью `WebSocket`. 

Если описать приложение *ReactiveStocks* на уровне классов, то получится примерно следующее:

{: .center}
![CPIBYQM.png](http://i.imgur.com/CPIBYQM.png)

<br>
Диаграмма последовательности, показывающая взаимодействие компонент с помощью сообщений, выглядит так:

{: .center}
![zMV2Bfy.png](http://i.imgur.com/zMV2Bfy.png)

Если описать словами, как события распространяются в системе и какие участники задействованы, то получится примерно следующее:

### [index.coffee]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee) ###

В [`index.coffee`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee) (то есть на клиенте, браузере) вызывается [`$`]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L1) (синоним `onLoad` в *JQuery*), в котором создается [канал двусторонней связи]({{page.reactive-stock-src}}app/assets/javascripts/index.coffee#L2) , основанный на *WebSocket*, связывающий клиент с вызовом `/ws`, т.е. фактически с вызовом статического метода [`controllers.Application.ws`]({{page.reactive-stock-src}}app/controllers/Application.java#L24) (см. также файл [`routes`]({{page.reactive-stock-src}}conf/routes#L6)). [`controllers.Application`]({{page.reactive-stock-src}}app/controllers/Application.java)) является основным веб-контроллером, который:

* возвращает индексную страницу (представленную темплейтом [`index.scala.html`]({{page.reactive-stock-src}}app/views/index.scala.html)); 
* Создает `WebSocket`, т.е. устанавливает двусторонний канал связи на стороне сервера; 
* Создает `UserActor` для каждого соединения с пользователем, т.е., `WebSocket`а (каждой открытой странице соответствует `WebSocket`), и передает `WebSocket`у ссылку на `UserActor`. 
* Принимает запросы на отслеживание котировки для переданного символа. 
* Инициирует отписку от обновлений котировок. 

### [Application]({{page.reactive-stock-src}}app/controllers/Application.java) и [WebSocket]({{page.reactive-stock-src}}app/controllers/Application.java#L25) ###

* В методе `controllers.Application.ws`, создается объект `WebSocket`. В последнем есть метод `onReady`, который является коллбеком 
инициализации и в который передаются 2 объекта - соответственно типов `WebSocket.In` и `WebSocket.Out` - т.е. входной и выходной каналы `WebSocket`а. Также в [`onReady`]({{page.reactive-stock-src}}app/controllers/Application.java#L26) первым делом инстанциируется `UserActor`, в который передается выходной канал `WebSocket`а для дальнейшей обратной связи.
* На каждый `WebSocket` приходится ровно один `UserActor`. 
* В ответ на запрос пользователя об отслеживании котировки, присылаемый через входной канал `WebSocket.In`, `WebSocket` генерирует сообщение [`WatchStock`]({{page.reactive-stock-src}}app/controllers/Application.java#L35), содержащее символ котировки к актору [`StocksActor`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L53) (который существует в единственном числе и является родительским актором по отношению к группе [`StockActor`ов]({{page.reactive-stock-src}}app/actors/StockActor.scala#L17), каждый из которых соответствует какой-то одной котировке, например, "GOOG"), указывая [`userActor`]({{page.reactive-stock-src}}app/controllers/Application.java#L37) в качестве отправителя, с тем чтобы ответные сообщения направлялись непосредственно в `userActor`. 
* Получив сообщение `WatchStock`, `StocksActor` (который один и родитель) [извлекает из `context`'а]({{page.reactive-stock-src}}app/actors/StockActor.scala#L57) (который имеет тип `ActorContext`) один из  `StockActor`ов - соответствующий переданному символу котировки, и если такого нету - создает его, а потом переадресовывает ему сообщение `WatchStock`.
* У входного канала веб-сокета есть [обработчик `onClose`]({{page.reactive-stock-src}}app/controllers/Application.java#L42); вызывается он в случае, если соединение с клиентом прервано. В нем отсылается сообщение `UnwatchStock` актору `StocksActor` (который родитель), который форвардит его всем своим `StockActor`ам, и последние удаляют отправителя (`UserActor`) из списка подписчиков, и если число подписчиков равно нулю - то `StockActor` останавливает себя.

### [StocksActor]({{page.reactive-stock-src}}app/actors/StockActor.scala#L53) ###
[`StocksActor`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L53) является актором-родителем для акторов [`StockActor`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L17):

* На сообщение [`WatchStock`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L55) он извлекает из контекста или создает соответсвующий переданному символу котировки `StockActor`, и форвардит сообщение этому актору;
* На сообщение [`UnwatchStock`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L60) - форвардит сообщение соответствующему `StockActor`у  - если сообщение `UnwatchStock` содержит символ котировки;
* Если сообщение [`UnwatchStock` не содержит символа]({{page.reactive-stock-src}}app/actors/StockActor.scala#L63), то сообщение `UnwatchStock` форвардится всем `context.children`.
  
### [StockActor]({{page.reactive-stock-src}}app/actors/StockActor.scala#L53) ###
Каждый [`StockActor`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L53) содержит множество подписчиков изменений котировок, хранятся они в поле [`watchers`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L21). В поле [`stockHistory`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L24) содержится история изменений цен, а поле [`stockQuote`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L19) есть тот самый сервисный объект, который собственно, значения цен и возвращает. Конкретно в данном случае, он инициализируется моковой реализацией - [`FakeStockQuote`]({{page.reactive-stock-src}}app/utils/FakeStockQuote.java#L8), который генерирует случайные значения цены. Поле [`stockTick`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L30) - планировщик, который  периодически высылает сообщение `FetchLatest` каждые 0.075 секунды. При инициализации `StockActor` сразу получает 50 начальных случайных значений цены для истории цен; каждое новое значение добавляется в конец очереди истории цен, а самый старый элемент удаляется, и таким образом размер очереди никогда не превышает 50 элементов.

* Сообщение `FetchLatest` регулярно высылается с помощью планировщика `stockTick`; в ответ на это сообщение `StockActor` [опрашивает `stockQuote`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L35) и добавляет полученную цену к `stockHistory` (удаляя первый элемент, чтобы очередь не превышала 50 элементов), и затем высылает сообщение `StockUpdate`, содержащее символ и новое значение цены всем своим подписчикам (которые являются акторами типа `UserActor`). 
* Поучив сообщение [`WatchStock`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L39), `StockActor` высылает сообщение `StockHistory` с 50 последними ценами отправителю сообщения `WatchStock`, и добавляет отправителя к множеству подписчиков (`watchers`) - собственно, механизм подписки реализован на сообщениях `WatchStock`.
* [В ответ на сообщение `UnwatchStock`]({{page.reactive-stock-src}}app/actors/StockActor.scala#L44), `StockActor` отписывает отправителя (т.е., удаляет его из множества `watchers`). Если больше не остается ни одного подписчика, то `StockActor` останавливает сначала планировщик `stockTick`, а затем и себя.

### [UserActor]({{page.reactive-stock-src}}app/actors/UserActor.java#L18) ###
[UserActor]({{page.reactive-stock-src}}app/actors/UserActor.java#L18) является подписчиком на сообщения `StockUpdate` and `StockHistory` от актора `StockActor`, и содержит [out-канал `WebSocket`а]({{page.reactive-stock-src}}app/actors/UserActor.java#L20), используемого для коммуникации с клиентом; `UserActor` может послать 2 вида JSON сообщений, а именно: `stockupdate` - который содержит символ котировки и значение цены, и `stockhistory` - который содержит опять-таки символ и массив из 50 последних значений котировки.

* Первое, что [`UserActor` делает после инициализации]({{page.reactive-stock-src}}app/actors/UserActor.java#L26) - он вычитывает список исходных котировок из конфигурационного параметра `"default.stocks"` и высылает сообщение `WatchStock` для каждого из вычитанных символов - чтобы подписаться на котировки из актора `StocksActor`. 
* Если `UserActor` [получает сообщение `StockUpdate` от одного из `StockActor`ов]({{page.reactive-stock-src}}app/actors/UserActor.java#L34), `UserActor` конвертирует сообщение в другое, JSON-сообщение `stockupdate`, которое понимает клиент, и [отсылает его через out-канал `WebSocket`а]({{page.reactive-stock-src}}app/actors/UserActor.java#L41) - т.е. проталкивает (*push*) его в клиентскую часть.
* Когда `UserActor` [получает сообщение `StockHistory`]({{page.reactive-stock-src}}app/actors/UserActor.java#L43) от одного из `StockActor`ов, `UserActor` затем конвертирует его в JSON-сообщение `stockhistory`, в котором, помимо символа, хранится массив последних значений цены и [записывает его в выходной канал `WebSocket`а]({{page.reactive-stock-src}}app/actors/UserActor.java#L56).

