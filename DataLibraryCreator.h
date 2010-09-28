//
//  Created by Karsten Kusche on 27.09.10.
//  Copyright 2010 Briksoftware.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DDCliApplication.h"


@interface DataLibraryCreator : NSObject <DDCliApplicationDelegate>{
	NSString* inFile;
	NSString* outFile;
	NSString* arch;
	NSString* symbolName;
}

@end
