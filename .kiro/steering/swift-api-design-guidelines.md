# Swift API Design Guidelines

*Content adapted from [Swift.org API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) for compliance with licensing restrictions*

## Table of Contents

- [Introduction](#introduction)
- [Fundamentals](#fundamentals)
- [Naming](#naming)
  - [Promote Clear Usage](#promote-clear-usage)
  - [Strive for Fluent Usage](#strive-for-fluent-usage)
  - [Use Terminology Well](#use-terminology-well)
- [Conventions](#conventions)
  - [General Conventions](#general-conventions)
  - [Parameters](#parameters)
  - [Argument Labels](#argument-labels)
- [Special Instructions](#special-instructions)

## Introduction

Delivering a clear, consistent developer experience when writing Swift code is largely defined by the names and idioms that appear in APIs. These design guidelines explain how to make sure that your code feels like a part of the larger Swift ecosystem.

## Fundamentals

- **Clarity at the point of use** is your most important goal. Entities such as methods and properties are declared only once but used repeatedly. Design APIs to make those uses clear and concise.

- **Clarity is more important than brevity.** Although Swift code can be compact, it is a non-goal to enable the smallest possible code with the fewest characters.

- **Write a documentation comment** for every declaration. Insights gained by writing documentation can have a profound impact on your design.

### Documentation Guidelines

- Use Swift's dialect of Markdown
- Begin with a summary that describes the entity being declared
- Focus on the summary; it's the most important part
- Use a single sentence fragment if possible, ending with a period
- Describe what a function or method does and what it returns
- Describe what a subscript accesses
- Describe what an initializer creates
- For all other declarations, describe what the declared entity is

Example:
```swift
/// Returns a "view" of `self` containing the same elements in reverse order.
func reversed() -> ReverseCollection<Self>
```

## Naming

### Promote Clear Usage

- **Include all the words needed to avoid ambiguity** for a person reading code where the name is used.

```swift
// Good
employees.remove(at: x)

// Bad - unclear intent
employees.remove(x) // are we removing x?
```

- **Omit needless words.** Every word in a name should convey salient information at the use site.

```swift
// Bad - redundant type information
public mutating func removeElement(_ member: Element) -> Element?
allViews.removeElement(cancelButton)

// Good - clearer without redundancy
public mutating func remove(_ member: Element) -> Element?
allViews.remove(cancelButton)
```

- **Name variables, parameters, and associated types according to their roles,** rather than their type constraints.

```swift
// Bad - names based on types
var string = "Hello"
func restock(from widgetFactory: WidgetFactory)

// Good - names based on roles
var greeting = "Hello"
func restock(from supplier: WidgetFactory)
```

- **Compensate for weak type information** to clarify a parameter's role.

```swift
// Bad - vague usage
func add(_ observer: NSObject, for keyPath: String)
grid.add(self, for: graphics) // vague

// Good - clear roles
func addObserver(_ observer: NSObject, forKeyPath path: String)
grid.addObserver(self, forKeyPath: graphics) // clear
```

### Strive for Fluent Usage

- **Prefer method and function names that make use sites form grammatical English phrases.**

```swift
x.insert(y, at: z)          // "x, insert y at z"
x.subviews(havingColor: y)  // "x's subviews having color y"
x.capitalizingNouns()       // "x, capitalizing nouns"
```

- **Begin names of factory methods with "make"**

```swift
x.makeIterator()
```

- **Name functions and methods according to their side-effects**
  - Those without side-effects should read as noun phrases: `x.distance(to: y)`
  - Those with side-effects should read as imperative verb phrases: `x.sort()`

- **Name Mutating/nonmutating method pairs consistently**
  - When naturally described by a verb, use imperative for mutating and past participle for nonmutating:

```swift
// Mutating
x.sort()
x.append(y)

// Nonmutating  
z = x.sorted()
z = x.appending(y)
```

- **Uses of Boolean methods and properties should read as assertions about the receiver**

```swift
x.isEmpty
line1.intersects(line2)
```

- **Protocols that describe what something is should read as nouns**

```swift
Collection
```

- **Protocols that describe a capability should use suffixes `able`, `ible`, or `ing`**

```swift
Equatable
ProgressReporting
```

### Use Terminology Well

- **Avoid obscure terms** if a more common word conveys meaning just as well
- **Stick to the established meaning** if you do use a term of art
- **Avoid abbreviations** - they are effectively terms-of-art
- **Embrace precedent** - don't optimize for total beginners at the expense of existing culture

## Conventions

### General Conventions

- **Document the complexity of any computed property that is not O(1)**
- **Prefer methods and properties to free functions** (exceptions: no obvious self, unconstrained generics, established domain notation)
- **Follow case conventions**: Types and protocols are `UpperCamelCase`, everything else is `lowerCamelCase`
- **Methods can share a base name** when they share the same basic meaning or operate in distinct domains

### Parameters

- **Choose parameter names to serve documentation**
- **Take advantage of defaulted parameters** when it simplifies common uses
- **Prefer to locate parameters with defaults toward the end** of the parameter list
- **If your API will run in production, prefer `#fileID`** over alternatives

### Argument Labels

- **Omit all labels when arguments can't be usefully distinguished**

```swift
min(number1, number2)
zip(sequence1, sequence2)
```

- **In initializers that perform value preserving type conversions, omit the first argument label**

```swift
Int64(someUInt32)
String(veryLargeNumber)
```

- **When the first argument forms part of a prepositional phrase, give it an argument label**

```swift
x.removeBoxes(havingLength: 12)
```

- **Otherwise, if the first argument forms part of a grammatical phrase, omit its label**

```swift
x.addSubview(y)
```

- **Label all other arguments**

## Special Instructions

- **Label tuple members and name closure parameters** where they appear in your API
- **Take extra care with unconstrained polymorphism** to avoid ambiguities in overload sets

Example of resolving ambiguity:
```swift
// Ambiguous
public mutating func append(_ newElement: Element)
public mutating func append<S: SequenceType>(_ newElements: S)

// Clear
public mutating func append(_ newElement: Element)  
public mutating func append<S: SequenceType>(contentsOf newElements: S)
```

---

*Content was rephrased for compliance with licensing restrictions*
