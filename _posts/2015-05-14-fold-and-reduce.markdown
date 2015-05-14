---
layout: post
title:  "Fold, aggregate, reduce и scan - II"
date:   2015-05-14 23:30:00
categories: scala
image: http://i.imgur.com/fI4DKrH.png
---

<script type="text/javascript" src="http://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML"></script>

<style>
table, th, td {
    border: 1px solid black;
    border-collapse: collapse;
}
th, td {
    padding: 5px;
    text-align: left;
}
.MathJax_Display {
  text-align: left !important;
}
</style>

### Scan

Иногда возникает необходимость не просто, например, посчитать сумму всех элементов, а накопить еще при этом все промежуточные результаты. Например,  посчитать последовательность Фибоначчи (`1, 1, 2, 4, 7, 11...`). Теоретически, это можно сделать с помощью `foldLeft`:

{% highlight scala %}
(0 until 6).foldLeft(List(1)){ (l,i) => (l.head + i) :: l }.reverse
{% endhighlight %}

Но есть более "прямой" путь - `scan`.

Немного теории. Возьмем, например, последовательность [треугольных чисел](https://en.wikipedia.org/wiki/Triangular_number) ($$n$$-е треугольное число — это сумма $$n$$ первых натуральных чисел):

<table>
  <tr>
    <th>входной список</th>
    <td>1</td>		
    <td>2</td>
    <td>3</td>		
    <td>4</td>
    <td>5</td>		
    <td>6</td>
    <td>...</td>
  </tr>
  <tr>
    <th>промежуточные суммы</th>
    <td>1</td>		
    <td>3</td>		
    <td>6</td>		
    <td>10</td>		
    <td>15</td>		
    <td>21</td>		
    <td>...</td>		
  </tr>
</table>
<br/>
*Префиксной суммой* (*prefix sum*) последовательности чисел $$x0, x1, x2, ...$$ называется другая последовательность чисел $$y0, y1, y2, ...,$$, состоящая из промежуточных сумм чисел входной последовательности:

<div align="text-align:right;">
$$
    y_0 = x_0
$$

$$
    y_1 = x_0 + x_1
$$

$$
    y_2 = x_0 + x_1+ x_2
$$
</div>

Частным случаем префиксных сумм натуральных чисел являются вышеприведенные треугольные числа.

В функциональном программировании, префиксная сумма может быть обобщена для любого оператора - не только сложения; результирующая функция высшего порядка называется `scan`, и она тесно связана со сверткой. И `scan`, и `fold` применяют некоторую бинарную операцию к последовательности значений, но `scan` возвращает последовательность результатов каждой операции, в то время как `fold` возвращает только конечный результат. Например, последовательность факториалов натуральных чисел

<table>
  <tr>
    <th>входной список</th>
    <td>1</td>		
    <td>2</td>
    <td>3</td>		
    <td>4</td>
    <td>5</td>		
    <td>6</td>
    <td>...</td>
  </tr>
  <tr>
    <th>промежуточные произведения</th>
    <td>1</td>		
    <td>2</td>		
    <td>6</td>		
    <td>24</td>		
    <td>120</td>		
    <td>720</td>		
    <td>...</td>		
  </tr>
</table>

может быть получена с помощью операции `scan` и функции, умножающей два числа:

{% highlight scala %}
scala> List(1,2,3,4,5,6).scanLeft(1)(_ * _)
res0: List[Int] = List(1, 1, 2, 6, 24, 120, 720)
{% endhighlight %}

В Scala, как и в случае с `fold`, есть 3 версии `scan`: `scanLeft`, `scanRight` и `scan`. 
В принципе, `scanLeft` можно записать через `foldLeft`  - со списком в качестве аккумулятора и вызовом `reverse` в конце:

{% highlight scala %}
def scanLeft[a,b](xs:Iterable[a])(s:b)(f : (b,a) => b) =
  xs.foldLeft(List(s))( (acc,x) => f(acc(0), x) :: acc).reverse
{% endhighlight %}

Ну и, конечно, можно отвлечься от сверток, и достичь того же самого эффекта, если использовать `map` с введением переменной ![gras](http://i.imgur.com/uWss0Qe.gif):

{% highlight scala %}
scala> List(1,2,3,4,5,6).map{var p = 1; x => {p *= x; p}}
res1: List[Int] = List(1, 2, 6, 24, 120, 720)
{% endhighlight %}

### Композиция трансформаций - конвейер

Конвейер в терминологии UNIX — некоторое множество процессов, для которых выполнено следующее перенаправление ввода-вывода: то, что выводит на поток стандартного вывода предыдущий процесс, попадает в поток стандартного ввода следующего процесса. Т.е. фактически это набор трансформаций над потоком данных. Эту модель, разумеется, можно использовать для разных видов данных,  необязательно только для ввода-вывода и только в контексте процессов. 
Для простоты представим, что мы работаем со строками. Трансформация - это функция, трансформирующая некий `String` в другой `String`, т.е. `String => String`. И мы хотим последовательно применить некторый динамический набор трансформаций в определенном порядке, т.е. нечто вроде:

{% highlight scala %}
def applyTransformations(initial: String, transformations: Seq[String => String])
{% endhighlight %}

И приведем примеры таких трансформаций:

{% highlight scala %}
val reverse = (s: String) => s.reverse
val toUpper = (s: String) => s.toUpperCase
val appendBar = (s: String) => s + "bar"
{% endhighlight %}

Т.е. в финале набор трансформаций должен превратиться в что-то вроде `(appendBar(toUpper(reverse("foo"))))`, что очень напоминает уже приведенный псевдокод свертки из предыдущей части - `f(f(f(f(z, a), b), c), d)`. И действительно, записать это с помощью `foldLeft` совсем несложно:
	
{% highlight scala %}
def applyTransformations(initial: String, transformations: Seq[String => String]) =
    transformations.foldLeft(initial) {
        (cur, transformation) => transformation(cur)
    }
{% endhighlight %}


