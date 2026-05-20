# Build Once. Work Live. Throw It Away.

Building the DevKit is the equivalent of building your project from source and running it.

In most languages, this is part of every code change. You edit source, build the project, run the application, test the result, then repeat. That process matters because it proves the source code can produce a working system.

It also slows you down.

Live development changes the shape of the work. In Smalltalk-style environments, the system keeps running while you inspect objects, change behaviour, run examples, and test ideas. Development continues inside the application instead of constantly stopping to rebuild and restart it.

That does not make the build less important. It makes the build less frequent.

A fresh DevKit build proves that the project can be loaded from source, configured, started, and tested from a clean base. Once that proof exists, you can work live without paying the rebuild cost after every change.

The discipline is simple:

```text
build the DevKit
run the tests and examples
work live
save the source
throw the DevKit away
```

The source is the product.  
The tests and examples are the proof.  
The DevKit is the working environment.

Do not make the DevKit precious. Build it at the start of a session, use it hard, then throw it away. The next session starts from source again.

That gives you the best part of live development: fast, direct work inside a real running system, without losing the confidence of a clean, reproducible build.
