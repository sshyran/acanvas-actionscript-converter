import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart';

const String DEFAULT_DART_PACKAGE = "autogen";
const String DEFAULT_AS_PACKAGE = "";
const String DEFAULT_SOURCE_DIR = "";
const String DEFAULT_TARGET_DIR = "lib";

String dart_package_name;
String as_package;
String source_basedir;
String target_basedir;

String package_file_content;


void main(List args) {

  _setupArgs(args);
  
  if(source_basedir == DEFAULT_SOURCE_DIR){
    print("Well, at least provide the --source dir, will you?");
    exit(1);
  }

  if(target_basedir == new File(target_basedir).absolute.path){
    print("Please provide a --target path relative to your working directory (the directory you're running this script from).");
    exit(1);
  }
  
  //prepare the package file so we can append all classes found
  package_file_content = 
'''
library $dart_package_name;

import 'dart:math';
import 'package:stagexl/stagexl.dart';
''';
  

  /* iterate over source path, grab *.as files */
  Directory sourceDir = new Directory(join(source_basedir, as_package));
  if (sourceDir.existsSync()) {
    sourceDir.listSync(recursive: true, followLinks: false).forEach((FileSystemEntity entity) {
      if (FileSystemEntity.typeSync(entity.path) == FileSystemEntityType.FILE && extension(entity.path).toLowerCase() == ".as") {
        _convert(entity.path);
      }
    });
    _writeTemplates();
    _addLibraryToRootPubspec();
  } else {
    print("The directory that was provided as source_basedir does not exist: $source_basedir");
    exit(1);
  }
}

/// Adds the newly created package as dependency to the project's root pubspec.yaml.
void _addLibraryToRootPubspec() {
  String insertionString = 
  '''
dependencies:
  $dart_package_name:
    path: ${join(target_basedir, dart_package_name)}''';
  
  File pubspecRootFile = new File('pubspec.yaml').absolute;
  String pubspecRootFileContent = pubspecRootFile.readAsStringSync();
  if(! pubspecRootFileContent.contains(dart_package_name)){
    pubspecRootFileContent = pubspecRootFileContent.split(new RegExp("dependencies\\s*:")).join(insertionString);
    pubspecRootFile.writeAsStringSync( pubspecRootFileContent, mode: FileMode.WRITE);
  }
}

/// Writes pubspec.yaml and package.dart into the newly created package.
void _writeTemplates() {
  //create package file
  new File(join(target_basedir, dart_package_name, "$dart_package_name.dart")).absolute
      ..createSync(recursive: true)
      ..writeAsStringSync(package_file_content);

  //create yaml file
  String pubspecFileContent =
'''
name: $dart_package_name
version: 0.1.0
description: $dart_package_name autogenerated dart lib
dependencies:
  stagexl: 
   git : https://github.com/bp74/StageXL.git
  logging: any
''';
  
  new File(join(target_basedir, dart_package_name, "pubspec.yaml")).absolute
      ..createSync(recursive: true)
      ..writeAsStringSync(pubspecFileContent);
}

/// Takes a File path, e.g. bin/examples/wonderfl/xmas/StarUnit.as, and writes it to
/// the output directory provided, e.g. lib/autogen/src/wonderfl/xmas/star_unit.dart.
/// During the process, excessive RegExp magic is applied.
void _convert(String asFilePath) {

  //e.g. bin/examples/wonderfl/xmas/StarUnit.as
  //print("asFilePath: $asFilePath");

  File asFile = new File(asFilePath);

  //File name, e.g. StarUnit.as
  String asFileName = basename(asFile.path);

  //Package name, e.g. wonderfl/xmas
  String dartFilePath = asFilePath.replaceFirst(new RegExp(source_basedir + "/"), "");
  dartFilePath = dirname(dartFilePath);
  //print("dartFilePath: $dartFilePath");

  //New filename, e.g. star_unit.dart
  String dartFileName = basenameWithoutExtension(asFile.path).replaceAllMapped(new RegExp("(IO|I|[^A-Z-])([A-Z])"), (Match m) => (m.group(1) + "_" + m.group(2))).toLowerCase();
  dartFileName += ".dart";
  //print("dartFileName: $dartFileName");

  String asFileContents = asFile.readAsStringSync();
  String dartFileContents = _applyMagic(asFileContents);

  //Write new file
  new File(join(target_basedir, dart_package_name, "src", dartFilePath, dartFileName)).absolute
      ..createSync(recursive: true)
      ..writeAsStringSync(dartFileContents);

  package_file_content += "\npart 'src/$dartFilePath/$dartFileName';";
}

/// Applies magic to an ActionScript file String, converting it to almost error free Dart.
/// Note that the focus lies on the conversion of the Syntax tree and the most obvious
/// differences in the respective API's.
String _applyMagic(String f) {
// replace package declaration
  f = f.replaceAllMapped(new RegExp("(\\s*)package\\s+[A-Za-z0-9.]+\\s*\\{"), (Match m) => "${m[1]} part of $dart_package_name;");
  // remove closing bracket at end of class
  f = f.replaceAll(new RegExp("\\}\\s*\$"), "");
  // reposition override keyword
  f = f.replaceAllMapped(new RegExp("(\\s+)override(\\s+)"), (Match m) => "${m[1]}@override${m[2]}\n\t\t");
  // remove Event Metadata
  f = f.replaceAllMapped(new RegExp("(\\[Event\\(.*\\])"), (Match m) => "// ${m[1]}");
  // remove Bindable Metadata
  f = f.replaceAllMapped(new RegExp("(\\[Bindable\\(.*\\])"), (Match m) => "// ${m[1]}");
  // replace interface
  f = f.replaceAll(new RegExp("interface"), "abstract class");
  // remove 'final' from class declaration
  f = f.replaceAll(new RegExp("final\\s+class"), "class");
  // delete imports
  f = f.replaceAll(new RegExp(".*import.*(\r?\n|\r)?"), "");
  // delete all scopes
  f = f.replaceAll(new RegExp("public|private|protected"), "");
  // convert * datatype
  f = f.replaceAll(new RegExp(":\\s*(\\*)"), ": dynamic");
  // convert Vector syntax and datatype (i.e. Vector.<int> to List<int>)
  f = f.replaceAllMapped(new RegExp("Vector.([a-zA-Z0-9_<>]*)"), (Match m) => "List${m[1]}");

  // === constructors and functions ===
  // note: the unprocessed function parameters are enclosed by '%#'
  //       marks. These are replaced later.

  // constructors (detected by missing return type)
  f = f.replaceAllMapped(new RegExp("([a-z]*)\\s+function\\s+(\\w*)\\s*\\(\\s*" + "([^)]*)" + "\\s*\\)(\\s*\\{)"), (Match m) => "\n\t${m[1]} ${m[2]}(%#${m[3]}%#)${m[4]}");

  // getters/setters
  f = f.replaceAllMapped(new RegExp("([a-z]*\\s+)function\\s+(get|set)\\s+(\\w*)\\s*\\(\\s*" + "([^)]*)" + "\\s*\\)\\s*:\\s*([a-zA-Z0-9_.<>]*)"), (Match m) => "${m[1]} ${m[5]} ${m[2]} ${m[3]}(%#${m[4]}%#)");
  // remove empty parentheses from getters
  f = f.replaceAllMapped(new RegExp("([a-zA-Z]*\\s+get\\s+\\w*\\s*)\\(%#%#\\)"), (Match m) => "${m[1]}");


  // functions
  f = f.replaceAllMapped(new RegExp("([a-z]*\\s+)function\\s+(\\w*)\\s*\\(\\s*" + "([^)]*)" + "\\s*\\)\\s*:\\s*([a-zA-Z0-9_.<>]*)"), (Match m) => "${m[1]} ${m[4]} ${m[2]}(%#${m[3]}%#)");

  // deal with super call in constructor
  f = f.replaceAllMapped(new RegExp("(\\s*\\{)\\s*(super\\s*\\(.*\\));"), (Match m) => ": ${m[2]} ${m[1]}");
  // disable super(this) in constructor
  f = f.replaceAll(new RegExp("(super\\s*\\(this\\))"), "super(/*this*/)");


  // remove zero parameter marks
  f = f.replaceAll(new RegExp("%#\\s*%#"), "");

  // Now, replace unprocessed parameters (maximum 9 parameters)
  for (int i = 0; i < 9; i++) {
    // parameters w/o default values
    f = f.replaceAllMapped(new RegExp("%#\\s*(\\w*)\\s*:\\s*([a-zA-Z0-9_.<>]*)\\s*,"), (Match m) => "${m[2]} ${m[1]},%#"); //first param of several
    f = f.replaceAllMapped(new RegExp("%#\\s*(\\w*)\\s*:\\s*([a-zA-Z0-9_.<>]*)\\s*%#"), (Match m) => "${m[2]} ${m[1]}"); //last or only param in declaration

    // parameters w/ default values. a bit tricky as dart has a special way of defining optional arguments
    //first find
    f = f.replaceAllMapped(new RegExp("%#\\s*(\\w*)\\s*:\\s*([a-zA-Z0-9_.<>]*)\\s*=\\s*([^):,]*)\\s*,"), (Match m) => "[${m[2]} ${m[1]}=${m[3]}, %##");
    //other finds
    f = f.replaceAllMapped(new RegExp("%##\\s*(\\w*)\\s*:\\s*([a-zA-Z0-9_.<>]*)\\s*=\\s*([^):,]*)\\s*,"), (Match m) => "${m[2]} ${m[1]}=${m[3]}, %##");
    //last find
    f = f.replaceAllMapped(new RegExp("%##\\s*(\\w*)\\s*:\\s*([a-zA-Z0-9_.<>]*)\\s*=\\s*([^):,]*)\\s*%#"), (Match m) => "${m[2]} ${m[1]}=${m[3]}]");

    //if only one param:
    f = f.replaceAllMapped(new RegExp("%#\\s*(\\w*)\\s*:\\s*([a-zA-Z0-9_.<>]*)\\s*=\\s*([^):,]*)\\s*%#"), (Match m) => "[${m[2]} ${m[1]}=${m[3]}]");
  }

  // === variable declarations ===
  f = f.replaceAllMapped(new RegExp("var\\s+([a-zA-Z0-9_]*)\\s*:\\s*([a-zA-Z0-9_.<>]*)"), (Match m) => "${m[2]} ${m[1]}");

  // === const declarations ===
  f = f.replaceAllMapped(new RegExp("const\\s+([a-zA-Z0-9_]*)\\s*:\\s*([a-zA-Z0-9_]*)"), (Match m) => "const ${m[2]} ${m[1]}");
  f = f.replaceAll(new RegExp("static const"), "static final");
  // XXX multiple comma separated declarations not supported!

  // === typecasts ===
  // int(value) --> value.toInt()
  f = f.replaceAllMapped(new RegExp("\\s+int\\s*\\((.+)\\)"), (Match m) => "(${m[1]}).toInt()");
  // (Class) variable --> (variable as Class)
  f = f.replaceAllMapped(new RegExp("\\(([a-zA-Z^)]+)\\)\\s*(\\w+)"), (Match m) => "(${m[2]} as ${m[1]})");
  // Class(variable) --> (variable as Class)
  f = f.replaceAllMapped(new RegExp("^new([A-Z]+[a-zA-Z0-9]+)\\s*\\(\\s*(\\w+)\\s*\\)"), (Match m) => "(${m[2]} as ${m[1]})");


  //e.g. _ignoredRootViews ||= new List<DisplayObject>();
  f = f.replaceAllMapped(new RegExp("(\\w+)\\s*\\|\\|\\=(.+);"), (Match m) => "(${m[1]} != null) ? ${m[1]} :${m[1]} = ${m[2]};");


  // === more translations ===
  f = f.replaceAll(new RegExp("Class"), "Type");
  f = f.replaceAll(new RegExp("Number"), "num");
  f = f.replaceAll(new RegExp("Boolean"), "bool");
  f = f.replaceAll(new RegExp("uint"), "int");
  f = f.replaceAll(new RegExp("Array"), "List");
  f = f.replaceAll(new RegExp("\\.push"), ".add");
  f = f.replaceAll(new RegExp("Vector"), "List");
  f = f.replaceAll(new RegExp("Dictionary"), "Map");
  f = f.replaceAllMapped(new RegExp("(\\s+)Object"), (Match m) => "${m[1]}Map");
  f = f.replaceAll(new RegExp("trace"), "print");
  f = f.replaceAll(new RegExp("for\\s+each"), "for");
  f = f.replaceAll(new RegExp("!=="), "==");
  f = f.replaceAll(new RegExp("==="), "==");
  f = f.replaceAll(new RegExp(">>>"), ">>/*>*/"); //strange one, used by frocessing package
  f = f.replaceAllMapped(new RegExp("^:\\s(super\\(\\s*\\))"), (Match m) => "// ${m[1]}");

  //Math
  f = f.replaceAll(new RegExp("Math\\.PI"), "PI");
  f = f.replaceAll(new RegExp("Math\\.max"), "/*Math.*/max");
  f = f.replaceAll(new RegExp("Math\\.tan"), "/*Math.*/tan");
  f = f.replaceAll(new RegExp("Math\\.sin"), "/*Math.*/sin");
  f = f.replaceAll(new RegExp("Math\\.cos"), "/*Math.*/cos");
  f = f.replaceAll(new RegExp("Math\\.min"), "/*Math.*/min");
  f = f.replaceAllMapped(new RegExp("Math\\.floor\\((.+)\\)"), (Match m) => "(${m[1]}).floor()");
  f = f.replaceAllMapped(new RegExp("Math\\.ceil\\((.+)\\)"), (Match m) => "(${m[1]}).ceil()");
  f = f.replaceAllMapped(new RegExp("Math\\.round\\((.+)\\)"), (Match m) => "(${m[1]}).round()");
  f = f.replaceAllMapped(new RegExp("Math\\.abs\\((.+)\\)"), (Match m) => "(${m[1]}).abs()");
  f = f.replaceAll(new RegExp("Math\\.random\\(\\)"), "new Random().nextDouble()");
  f = f.replaceAllMapped(new RegExp("toFixed\\((\\d+)\\)"), (Match m) => "toStringAsFixed(${m[1]})");


  // === StageXL specific ===

  //change the order of color and fill instructions for Graphics and BitmapData
  f = f.replaceAllMapped(new RegExp("([a-zA-Z0-9\.]+beginFill\\(\\s*[a-fA-F0-9x]+\\s*\\)\\s*;)(\r?\n|\r)?(\\s*)([a-zA-Z0-9\.]+(drawRect|drawRoundRect)\\(\\s*[a-zA-Z0-9\.\\s*,\\s*]+\\s*\\)\\s*;)"), (Match m) => "${m[4]}${m[2]}${m[3]}${m[1]} //");
  //renaming
  f = f.replaceAll(new RegExp("beginFill"), "fillColor");
  f = f.replaceAll(new RegExp("drawRect"), "rect");
  f = f.replaceAll(new RegExp("drawRoundRect"), "rectRound");
  //endFill not supported/needed
  f = f.replaceAllMapped(new RegExp("([a-zA-Z0-9\.]+endFill\\(\\s*\\))"), (Match m) => "//${m[1]} //not supported in StageXL");
  //lock/unlock not supported/needed
  f = f.replaceAllMapped(new RegExp("([a-zA-Z0-9\.]+(lock|unlock)\\(\\s*\\))"), (Match m) => "//${m[1]} //not supported in StageXL");
  //smoothing not supported
  f = f.replaceAllMapped(new RegExp("([a-zA-Z0-9\.]+smoothing\\s*=\\s*.+;)"), (Match m) => "//${m[1]} //not supported in StageXL");

  //help out with TweenLite/TweenMax
  f = f.replaceAllMapped(new RegExp("(\\s*)(TweenLite|TweenMax)(\\.to\\(\\s*)([a-zA-Z0-9\.]+)(\\s*,\\s*[a-zA-Z0-9\.]+)(.+;)"), (Match m) => "${m[1]}${m[1]}//TODO ${m[1]}/* ${m[1]}//StageXL tweening works like this: ${m[1]}stage.juggler.tween(${m[4]} ${m[5]} /*, TransitionFunction.easeOutBounce */)${m[1]}  .animate.x.to( someValue ); ${m[1]}*/ ${m[1]}${m[2]}${m[3]}${m[4]}${m[5]}${m[6]}${m[1]}");

  //Geometry
  f = f.replaceAll(new RegExp("new\\s+Point\\(\\)"), "new Point(0,0)");

  //Timer
  f = f.replaceAll(new RegExp("getTimer\\(\\)"), "/*getTimer()*/ (stage.juggler.elapsedTime*1000)");

  //no IEventDispatcher in StageXL
  f = f.replaceAll(new RegExp("IEventDispatcher"), "/*I*/EventDispatcher");

  //when testing for null, this works in as3: if(variable). In Dart, everything other than a bool needs if(variable != null)
  f = f.replaceAllMapped(new RegExp("if\\s*\\(\\s*([a-zA-Z0-9]+)\\s*\\)"), (Match m) => "if( ${m[1]} != null || ${m[1]} == true)");
  f = f.replaceAllMapped(new RegExp("if\\s*\\(\\s*!\\s*([a-zA-Z0-9]+)\\s*\\)"), (Match m) => "if( ${m[1]} == null || ${m[1]} == false)");

  return f;
}

/// Manages the script's arguments and provides instructions and defaults for the --help option.
void _setupArgs(List args) {
  ArgParser argParser = new ArgParser();
  argParser.addOption('dart-package', abbr: 'd', defaultsTo: DEFAULT_DART_PACKAGE, help: 'The name of the package to be generated.', valueHelp: 'package', callback: (_dpackage) {
    dart_package_name = _dpackage;
  });
  argParser.addOption('as-package', abbr: 'a', defaultsTo: DEFAULT_AS_PACKAGE, help: 'The as3 package to be converted, e.g. com/my/package. If omitted, everything found under the --source directory provided will get converted.', valueHelp: 'package', callback: (_apackage) {
    as_package = _apackage;
  });
  argParser.addOption('source', abbr: 's', defaultsTo: DEFAULT_SOURCE_DIR, help: 'The path (relative or absolute) to the Actionscript source(s) to be converted.', valueHelp: 'source', callback: (_source_basedir) {
    source_basedir = _source_basedir;
  });
  argParser.addOption('target', abbr: 't', defaultsTo: DEFAULT_TARGET_DIR, help: 'The path (relative!) the generated Dart package will be written to. Usually, your Dart project\'s \'lib\' directory.', valueHelp: 'target', callback: (_target_basedir) {
    target_basedir = _target_basedir;
  });


  argParser.addFlag('help', negatable: false, help: 'Displays the help.', callback: (help) {
    if (help) {
      print(argParser.getUsage());
      exit(1);
    }
  });

  argParser.parse(args);
}
