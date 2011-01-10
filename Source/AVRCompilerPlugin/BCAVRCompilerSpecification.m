//
//  BCAVRCompilerSpecification.m
//  AVRCompilerPlugin
//
//  Created by Jeremy Knope on 1/4/11.
//  Copyright 2011 Buttered Cat Software. All rights reserved.
//

#import "BCAVRCompilerSpecification.h"

#import "XCPBuildSystem.h"
#import "XCPDependencyGraph.h"
#import "XCPSupport.h"

@implementation BCAVRCompilerSpecification

+ (void)initialize {
	PBXFileType *type = (PBXFileType*)[PBXFileType specificationForIdentifier:@"sourcecode.pde"];
	XCCompilerSpecification *spec = (XCCompilerSpecification*)[XCCompilerSpecification specificationForIdentifier:@"com.buttered-cat.compilers.avr"];
	[PBXTargetBuildContext activateImportedFileType:type withCompiler:spec];
}

- (id)doSpecialDependencySetupForCommand:(id)arg1 withInputNodes:(id)arg2 inBuildContext:(PBXTargetBuildContext *)context
{
	id result = [super doSpecialDependencySetupForCommand:arg1 withInputNodes:arg2 inBuildContext:context];
	NSLog(@"(GCC) args(%@, %@) Super result: %@", arg1, arg2, result);
	return result;
}

- (NSArray *)importedFilesForPath:(NSString *)path ensureFilesExist:(BOOL)ensure inTargetBuildContext:(PBXTargetBuildContext *)context
{
	return [NSArray array];
	//	NSString* outputDir = [context expandedValueForString:@"$(OBJFILES_DIR_$(variant))/$(arch)"];
	XCDependencyNode* inputNode = [context dependencyNodeForName:path createIfNeeded:YES];
	
	NSSet *filenames = nil; //DXSourceDependenciesForPath([NSString stringWithContentsOfFile:path]);
	NSMutableArray *imported = [NSMutableArray arrayWithCapacity:[filenames count]];
	
	NSEnumerator *e = [filenames objectEnumerator];
	NSString *filename;
	while (filename = [e nextObject]) {
		NSString *filepath = [context absolutePathForPath:filename];
		XCDependencyNode *node = [context dependencyNodeForName:filepath createIfNeeded:YES];
		[node setDontCareIfExists:YES];
		[inputNode addIncludedNode:node];
		[imported addObject:filename];
		
		//		if ([context expandedBooleanValueForString:@"$(GDC_GENERATE_INTERFACE_FILES)"] &&
		//			[filepath hasSuffix:@".d"])
		//		{
		//			NSString *objRoot = [context expandedValueForString:@"$(OBJROOT)"];
		//			NSString *interfaceDir = [objRoot stringByAppendingPathComponent:@"dinterface"];
		//			NSString *interfaceFile = [interfaceDir stringByAppendingPathComponent:[filepath stringByAppendingPathExtension:@"di"]];
		//			
		//			node = [context dependencyNodeForName:interfaceFile createIfNeeded:YES];
		//			[node setDontCareIfExists:YES];
		//			[inputNode addIncludedNode:node];
		//			[imported addObject:filename];
		//		}
	}
	
	return imported;
}


- (NSArray *)computeDependenciesForInputFile:(NSString *)input ofType:(PBXFileType*)type variant:(NSString *)variant architecture:(NSString *)arch outputDirectory:(NSString *)outputDir inTargetBuildContext:(PBXTargetBuildContext *)context
{
	// compute input file path
	input = [context expandedValueForString:input];
	
	// compute output file path
	NSString *basePath = [input stringByDeletingPathExtension];
	NSString *relativePath = [context naturalPathForPath:basePath];
	NSString *baseName = [relativePath stringByReplacingCharacter:'/' withCharacter:'.'];
	NSString *output = [baseName stringByAppendingPathExtension:@"o"];
	output = [outputDir stringByAppendingPathComponent:output];
	output = [context expandedValueForString:output];
	
	// create dependency nodes 
	XCDependencyNode *outputNode = [context dependencyNodeForName:output createIfNeeded:YES];
	XCDependencyNode *inputNode = [context dependencyNodeForName:input createIfNeeded:YES];
	
	// create compiler command
	XCDependencyCommand *dep = [context
								createCommandWithRuleInfo:[NSArray arrayWithObjects:@"avr-gcc", [context naturalPathForPath:input],nil]
								commandPath:[context expandedValueForString:[self path]]
								arguments:nil
								forNode:outputNode];
	[dep setToolSpecification:self];
	[dep addArgumentsFromArray:[self commandLineForAutogeneratedOptionsInTargetBuildContext:context]];
	[dep addArgumentsFromArray:[[context expandedValueForString:@"$(build_file_compiler_flags)"] arrayByParsingAsStringList]];
	//[dep addArgumentsFromArray:[[context expandedValueForString:@"$(HEADER_SEARCH_PATHS)"] arrayByParsingAsStringList]];
	// Need to handle this flag programatically to avoid clashing with zerolink.
//	if([context expandedBooleanValueForString:@"$(GDC_DYNAMIC_NO_PIC)"]) {
//		if(![context expandedBooleanValueForString:@"$(ZERO_LINK)"]) {
//			[dep addArgument:@"-mdynamic-no-pic"];
//		}
//	}
	
	[dep addArgument:[NSString stringWithFormat:@"-mmcu=%@", arch]];
	
	[dep addArgument:@"-c"];
	[dep addArgument:input];
	[dep addArgument:@"-o"];
	[dep addArgument:output];
	
	// Create dependency rules (must be done after dependency command creation)
	[outputNode addDependedNode:inputNode];
	
	// Tell Xcode to use the GDC linker.
	[context setStringValue:@"com.buttered-cat.avr.linker" forDynamicSetting:@"compiler_mandated_linker"];
	// This fixes link problem for Xcode 3.1.
	[context setStringValue:@"/usr/local/CrossPack-AVR/bin/avr-gcc" forDynamicSetting:@"gcc_compiler_driver_for_linking"];
	NSString *linkerFlags = [NSString stringWithFormat:@"-lm $(SDKROOT)/arduino/libArduinoCore.$(arch).a", [context expandedValueForString:@"$(SDKROOT)"]];
	[context addCompilerRequestedLinkerParameters:[NSDictionary dictionaryWithObject:linkerFlags forKey:@"ALL_OTHER_LDFLAGS"]];
	//NSLog(@"Linker flags via compiler: %@", [context compilerRequestedLinkerParameters]);
	//	if ([context expandedBooleanValueForString:@"$(GDC_GENERATE_INTERFACE_FILES)"]) {
	//		NSString *objRoot = [context expandedValueForString:@"$(OBJROOT)"];
	//		NSString *interfaceDir = [objRoot stringByAppendingPathComponent:@"dinterface"];
	//		[dep addArgument:@"-I"];
	//		[dep addArgument:interfaceDir];
	//		
	//		NSString *interfaceFile = [interfaceDir stringByAppendingPathComponent:[relativePath stringByAppendingPathExtension:@"di"]];
	//		[dep addArgument:[NSString stringWithFormat:@"-fintfc-file=%@", interfaceFile]];
	//	}
	
	// update source <-> output links
	[context setCompiledFilePath:output forSourceFilePath:input];
	
	// set output objects
	return [NSArray arrayWithObject:outputNode];
}

@end
