#!/usr/bin/env tclsh
package require tcltest
namespace import ::tcltest::*
configure -testdir [file dirname [info script]] -verbose {pass fail error}
runAllTests
exit [expr {$::tcltest::numTests(Failed) > 0}]
