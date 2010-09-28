//
//  Created by Karsten Kusche on 27.09.10.
//  Copyright 2010 Briksoftware.com. All rights reserved.
//
/*
 
 The main work is done in:
 - (void)convertFrom: (NSString*)source to:(NSString*)target
 
 the idea is to compile an dummy Assembler file into an object file, link that into a static library
 the static library will have a placeholder inside which consists of 0x33s.
 The placeholder is replaced by the contents of the <source> file and the resulting file is stored in <target>

 There are two globals defined in the Assembler file:
 "name" and "name_size", where "name" is what you pass to the tool in the -n switch
 In your c project you can then link to the static library and declare the data via "extern char* name;" and "extern long name_size;"
 
 */
#import "DataLibraryCreator.h"
#import "DDCliUtil.h"
#import "DDGetoptLongParser.h"

static unsigned char spaceByte = 0x33;

@implementation DataLibraryCreator

- (NSString*)tempFolder
{
	static NSString *tempDirectoryPath = nil;
	if (tempDirectoryPath == nil)
	{
		NSString *tempDirectoryTemplate = [NSTemporaryDirectory() stringByAppendingPathComponent:@"DataCreator.XXXXXX"];
		const char *tempDirectoryTemplateCString = [tempDirectoryTemplate fileSystemRepresentation];
		char *tempDirectoryNameCString = (char *)malloc(strlen(tempDirectoryTemplateCString) + 1);
		strcpy(tempDirectoryNameCString, tempDirectoryTemplateCString);
		
		char *result = mkdtemp(tempDirectoryNameCString);
		if (!result)
		{
			return nil;
		}
		tempDirectoryPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:tempDirectoryNameCString
																						length:strlen(result)];
		free(tempDirectoryNameCString);
//		NSLog(@"temps at: %@",tempDirectoryPath);
	}
	return tempDirectoryPath;
}

- (void)showError:(NSString*)errorMessage
{
	ddfprintf(stderr, @"error: %@\n\
			  \n\
			  parameter: \n\
			  -n name -- symbol name -- will create a <name> and <name_size> variable\n\
			  -s file -- source file\n\
			  [-o file] -- out file -- defaults to stdout\n\
			  [-a arch] -- architecture -- defaults to current arch\n",errorMessage);
	[[NSFileManager defaultManager] removeItemAtPath:[self tempFolder] error:nil];
	exit(EXIT_FAILURE);
}

- (NSString*)pathForFile:(NSString*) path withExtention:(NSString*)extention
{
//	NSString* folder = [path stringByDeletingLastPathComponent];
	NSString* file = [[path lastPathComponent] stringByDeletingPathExtension];
	
	return [[[self tempFolder] stringByAppendingPathComponent:file]stringByAppendingPathExtension:extention];
}

- (NSString*)createAsFile: (NSString*)path forSize:(NSUInteger)size
{
	NSString* asFile = [self pathForFile:path withExtention:@"s"];
	NSString* sizeString = [[NSNumber numberWithUnsignedInteger:size] stringValue];
	NSString* contents = [NSString stringWithFormat:@".section __DATA,__data\n\
						  _%@_holder: \n\
						  .space %@,%i\n\
						  .globl _%@\n\
						  _%@:\n\
						  .quad _%@_holder\n\
						  .long 0xfeedface\n\
						  .globl _%@_size\n\
						  _%@_size:\n\
						  .long %@\n",symbolName,sizeString,spaceByte,symbolName,symbolName,symbolName,symbolName,symbolName,sizeString];
	if ([contents writeToFile:asFile atomically:YES encoding:NSUTF8StringEncoding error:nil])
	{
		return asFile;
	}
	return nil;
}

- (BOOL)executeScript:(NSString*)script
{
	const char* command;
	command = [script UTF8String];
	return system(command) != -1;		
}

- (NSString*)assembleFile:(NSString*)asFile
{
	NSString* archString = @"";
	if (arch)
	{
		archString = [NSString stringWithFormat:@"-arch %@",arch];
	}
	NSString* oFile = [self pathForFile:asFile withExtention:@"o"];
	NSString* script = [NSString stringWithFormat:@"as %@ %@ -o %@",archString,asFile,oFile];
	if ([self executeScript:script])
	{
		return oFile;
	}
	return nil;
}

- (NSString*)linkFile:(NSString*)oFile
{
	NSString* aFile = [self pathForFile:oFile withExtention:@"a"];
	if ([self executeScript:[NSString stringWithFormat:@"libtool %@ -o %@",oFile, aFile]])
	{
		return aFile;
	}
	return nil;
}

- (void)copy:(long) numBytes bytesFrom: (FILE*)fromFile to: (FILE*)toFile
{
	char smallBuffer = '\0';
	int smallBytes = numBytes % sizeof(long);
	long bigBuffer = 0;
	long bigBytes = (numBytes - smallBytes) / sizeof(long);
	long i;
	for (i = 0; feof(fromFile) == NO && i < smallBytes; i++)
	{
		fread(&smallBuffer, 1, 1, fromFile);
		fwrite(&smallBuffer, 1, 1, toFile);
	}
	for (i = 0; feof(fromFile) == NO && i < bigBytes; i++)
	{
		long numRead = fread(&bigBuffer,1,sizeof(long),fromFile);
		fwrite(&bigBuffer,1,numRead,toFile);
	}
}

- (BOOL)patchFile:(NSString*)aFileName withContentsFrom:(NSString*)sourceFile to:(NSString*)target
{
	FILE* aFile = fopen([aFileName fileSystemRepresentation],"r");
	FILE* dataFile = fopen([sourceFile fileSystemRepresentation],"r");
	FILE* targetFile = fopen([target fileSystemRepresentation],"w");
	
	// get dataFile's size
	fseek(dataFile, 0, SEEK_END);
	long dataFileSize = ftell(dataFile);
	rewind(dataFile);
	
	// find the placeholder in aFile.
	long size = 0;
	long start = 0;
	while (feof(aFile) == NO && size != dataFileSize)
	{
		unsigned char byte = '\0';
		// search until the start of the placeholder
		while (feof(aFile) == NO && byte != spaceByte)
		{
			fread(&byte, sizeof(byte), 1, aFile);
		}
		start = ftell(aFile) - 1;
		// search until the end of the placeholder
		while (feof(aFile) == NO && byte == spaceByte)
		{
			fread(&byte, sizeof(byte), 1, aFile);
		}
		size = (ftell(aFile) - 1) - start;
	}
	
	if (feof(aFile) == YES)
	{
		[self showError:@"can't find placeholder in file"];
		return NO;
	}
	
	rewind(aFile);
	[self copy: start bytesFrom: aFile to: targetFile];
	[self copy: size bytesFrom: dataFile to: targetFile];
	fseek(aFile, size, SEEK_CUR);
	[self copy: LONG_MAX bytesFrom: aFile to: targetFile];
	
	fclose(aFile);
	fclose(dataFile);
	fclose(targetFile);
	return YES;
}

- (void)convertFrom: (NSString*)source to:(NSString*)target
{
	NSDictionary* fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:source error:nil];
	NSUInteger fileSize = [[fileAttributes objectForKey:NSFileSize] unsignedIntegerValue];
	if (!fileSize) {[self showError:@"invalid input"]; return;}

	NSString* asFile = [self createAsFile:target forSize:fileSize];
	if (!asFile) {[self showError:@"can't create .s file"]; return;}

	NSString* oFile = [self assembleFile: asFile];
	if (!oFile) { [self showError: @"can't create .o file"]; return;}
	
	NSString* aFile = [self linkFile: oFile];
	if (!aFile) { [self showError: @"can't create .a file"]; return;}
	
	BOOL couldReplaceContents = [self patchFile: aFile withContentsFrom:source to:target];
	if (!couldReplaceContents) {[self showError:@"can't replace contents"]; return;}
	
}


- (int)application:(DDCliApplication *)app
  runWithArguments:(NSArray *)arguments
{
	NSString* sourceFile = nil;
	NSString* output = @"/dev/stdout";
	if (symbolName == nil)
	{
		[self showError:@"no symbol name provided"];
	}
	if (inFile) {
		sourceFile = [inFile stringByExpandingTildeInPath];
	}
	else
	{
		[self showError:@"no imput file provided"];
	}
	if (arch == nil) {
		SInt32 gestaltValue;
		Gestalt(gestaltSysArchitecture, &gestaltValue);
		if (gestaltValue == gestaltPowerPC)
		{
			arch = @"ppc";
		}
		else
		{
			if (sizeof(NSInteger) == sizeof(int))
			{
				arch = @"i386";
			}
			else
			{
				arch = @"x86_64";
			}
		}
	}
	if (outFile)
	{
		output = [outFile stringByExpandingTildeInPath];
	}
	[self convertFrom: sourceFile to: output];
    return EXIT_SUCCESS;
	
}

- (void)application:(DDCliApplication *)app
   willParseOptions:(DDGetoptLongParser *)optionsParser
{
	outFile = nil;
	inFile = nil;
	arch = nil;
	DDGetoptOption optionTable[] = 
    {
		// Long         Short   Argument options
		{@"inFile",        's',    DDGetoptRequiredArgument},
		{@"outFile",        'o',    DDGetoptRequiredArgument},
		{@"symbolName",    'n',    DDGetoptRequiredArgument},
		{@"verbose",       'v',    DDGetoptNoArgument},
		{@"arch",          'a',    DDGetoptRequiredArgument},
		{nil,           0,      0}
    };
    [optionsParser addOptionsFromTable:optionTable];
}

@end

int main(int argc, char* argv[])
{
	return DDCliAppRunWithDefaultClass();
}