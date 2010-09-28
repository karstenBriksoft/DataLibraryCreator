##About
DataLibraryCreator is a tool to convert any binary file to a static library with two exported symbols, that can be linked to your application so that you can access the binary file's data via the exported symbols. The exported symbols are a pointer to the bytes and a variable containing the size of the binary data.

#Usage
DataLibraryCreator -s inputFile -n symbolName -o dataLib.a

that reads the input file and creates the symbols "symbolName" and "symbolName_size". You can then link to the dataLib.a in your project.

#Implementation
The tricky part is to create the object file that contains the binary data. This is done using the assembler "as" and letting it create a space of enough bytes with a certain byte as placeholder.
This placeholder is then searched and replaced with the binary data.
Creating a static library from the object file is done using Libtool.