//
//  DVTTextCompletionController+SCXcodeSwitchExpander.m
//  SCXcodeSwitchExpander
//
//  Created by Stefan Ceriu on 13/03/2014.
//  Copyright (c) 2014 Stefan Ceriu. All rights reserved.
//

#import "DVTTextCompletionController+SCXcodeSwitchExpander.h"

#import "SCXcodeSwitchExpander.h"

#import "DVTSourceTextView.h"

#import "IDEIndex.h"
#import "IDEIndexCollection.h"
#import "IDEIndexCompletionItem.h"
#import "IDEIndexContainerSymbol.h"
#import "DVTSourceCodeSymbolKind.h"

#import "DVTTextCompletionSession.h"

#import <objc/objc-class.h>

/// Returns symbol names from swift style full symbol name (e.g. from `Mirror.DisplayStyle` to `[Mirror, DisplayStyle]`).
NSArray<NSString*>* symbolNamesFromFullSymbolName(NSString* fullSymbolName);

/// Returns normalized symbol name for -[IDEIndex allSymbolsMatchingName:kind:].
NSString* normalizedSymbolName(NSString* symbolName);

/// Returns a symbol name removed swift generic parameter (e.g. `SomeType<T>` to `SomeType`).
NSString* symbolNameRemovingGenericParameter(NSString* symbolName);

/// Returns a symbol name replaced syntax suggered optional to formal type name type in Swift (e.g. `Int?` to `Optional).
NSString* symbolNameReplacingOptionalName(NSString* symbolName);

NSArray<NSString*>* symbolNamesFromFullSymbolName(NSString* fullSymbolName)
{
    NSMutableArray<NSString*> *names = [[fullSymbolName componentsSeparatedByString:@"."] mutableCopy];
    
    for (NSInteger nameIndex = 0; nameIndex != names.count; ++nameIndex)
    {
        names[nameIndex] = normalizedSymbolName(names[nameIndex]);
    }
    
    return [names copy];
}

NSString* normalizedSymbolName(NSString* symbolName)
{
    NSString *result = symbolName;
    
    result = symbolNameRemovingGenericParameter(result);
    result = symbolNameReplacingOptionalName(result);
    
    return result;
}

NSString* symbolNameRemovingGenericParameter(NSString* symbolName)
{
    if ([[SCXcodeSwitchExpander sharedSwitchExpander] isSwift])
    {
        return [symbolName stringByReplacingOccurrencesOfString:@"<[^>]+>$"
                                               withString:@""
                                                  options:NSRegularExpressionSearch
                                                    range:NSMakeRange(0, symbolName.length)];
    }
    else
    {
        return symbolName;
    }
}

NSString* symbolNameReplacingOptionalName(NSString* symbolName)
{
    if ([[SCXcodeSwitchExpander sharedSwitchExpander] isSwift])
    {
        if ([symbolName hasSuffix:@"?"])
        {
            return @"Optional";
        }
        else if ([symbolName hasSuffix:@"!"])
        {
            return @"ImplicitlyUnwrappedOptional";
        }
        else
        {
            return symbolName;
        }
    }
    else
    {
        return symbolName;
    }
}

@interface DVTTextCompletionListWindowController (SCXcodeSwitchExpander)

- (BOOL)tryExpandingSwitchStatement;

/// Returns symbols that found in top `collection` by names recursively.
- (NSArray<IDEIndexSymbol*>*)findSymbolsWithNames:(NSArray<NSString*>*)names fromCollection:(IDEIndexCollection*)collection;

/// Returns symbols named `name` in `collection`
- (NSArray<IDEIndexSymbol*>*)_getSymbolsByName:(NSString*)name fromCollection:(IDEIndexCollection*)collection;

/// Returns symbols named `name[0].name[1].name[2]...` in `collection` recursively.
- (NSArray<IDEIndexSymbol*>*)_getSymbolsByNames:(NSArray<NSString*>*)names fromCollection:(IDEIndexCollection*)collection;

/// Returns a boolean value whether `symbolKind` means a enum type.
- (BOOL)isSymbolKindEnum:(DVTSourceCodeSymbolKind *)symbol;

/// Returns a boolean value whether `symbolKind` means a enum constant.
- (BOOL)isSymbolKindEnumConstant:(DVTSourceCodeSymbolKind *)symbolKind;

@end

@implementation DVTTextCompletionController (SCXcodeSwitchExpander)

+ (void)load
{
    Method originalMethod = class_getInstanceMethod(self, @selector(acceptCurrentCompletion));
    Method swizzledMethod = class_getInstanceMethod(self, @selector(scSwizzledAcceptCurrentCompletion));
    
    if ((originalMethod != nil) && (swizzledMethod != nil)) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

- (BOOL)scSwizzledAcceptCurrentCompletion
{
	if([self.currentSession.listWindowController tryExpandingSwitchStatement]) {
		return YES;
	}
	
	return [self scSwizzledAcceptCurrentCompletion];
}

@end

@implementation DVTTextCompletionListWindowController (SCXcodeSwitchExpander)

- (NSArray<IDEIndexSymbol*>*)_getSymbolsByName:(NSString*)name fromCollection:(IDEIndexCollection*)collection
{
    NSMutableArray<IDEIndexSymbol*> *results = [[NSMutableArray alloc] init];
    
    for (IDEIndexSymbol *symbol in collection)
    {
        if ([symbol.name isEqualToString:name])
        {
            [results addObject:symbol];
        }
    }
    
    return [results copy];
}

- (NSArray<IDEIndexSymbol*>*)_getSymbolsByNames:(NSArray<NSString*>*)names fromCollection:(IDEIndexCollection*)collection
{
    NSString* name = names.firstObject;
    NSArray<NSString*> *subNames = [names subarrayWithRange:NSMakeRange(1, names.count - 1)];
    
    for (IDEIndexSymbol *symbol in collection)
    {
        if ([symbol.name isEqualToString:name] && [symbol isKindOfClass:[IDEIndexContainerSymbol class]])
        {
            NSArray<IDEIndexSymbol*>* symbols = [self findSymbolsWithNames:subNames fromCollection:[(IDEIndexContainerSymbol*)symbol children]];
        
            if (symbols.count > 0)
            {
                return symbols;
            }
        }
    }
    
    return nil;
}

- (NSArray<IDEIndexSymbol*>*)findSymbolsWithNames:(NSArray<NSString*>*)names fromCollection:(IDEIndexCollection*)collection
{
    switch (names.count)
    {
        case 0:
            return @[];
            
        case 1:
            return [self _getSymbolsByName:names.firstObject fromCollection:collection];
            
        default:
            return [self _getSymbolsByNames:names fromCollection:collection];
    }
}

- (NSArray<IDEIndexSymbol*>*)getSymbolsByFullName:(NSString*)fullSymbolName fromIndex:(IDEIndex*)index
{
    NSArray<NSString*> *names = symbolNamesFromFullSymbolName(fullSymbolName);
    IDEIndexCollection *collection = [index allSymbolsMatchingName:names.firstObject kind:nil];

    return [self findSymbolsWithNames:names fromCollection:collection];
}

- (BOOL)tryExpandingSwitchStatement
{
    IDEIndex *index = [[SCXcodeSwitchExpander sharedSwitchExpander] index];
    
    if(index == nil) {
        return NO;
    }
    
    IDEIndexCompletionItem *item = [self _selectedCompletionItem];
    
    // Fetch all symbols matching the autocomplete item type
	NSString *symbolName = (item.displayType.length ? item.displayType : item.displayText);
	symbolName = [[symbolName componentsSeparatedByString:@"::"] lastObject]; // Remove C++ namespaces
	symbolName = [[symbolName componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] lastObject]; // Remove enum keyword

    NSArray<IDEIndexSymbol*> *symbols = [self getSymbolsByFullName:symbolName fromIndex:index];
	
    // Find the first one of them that is a container
    for(IDEIndexSymbol *symbol in symbols) {
        
        DVTSourceCodeSymbolKind *symbolKind = symbol.symbolKind;
		
        BOOL isSymbolKindEnum = NO;
        for(DVTSourceCodeSymbolKind  *conformingSymbol in symbolKind.allConformingSymbolKinds) {
            isSymbolKindEnum = [self isSymbolKindEnum:conformingSymbol];
        }
        
        if (!isSymbolKindEnum) {
			return NO;
        }
        
        if(symbolKind.isContainer) {
            
            DVTSourceTextView *textView = (DVTSourceTextView *)self.session.textView;
            if(self.session.wordStartLocation == NSNotFound) {
                return NO;
            }
            
            // Fetch the previous new line
            NSRange newLineRange = [textView.string rangeOfString:@"\n" options:NSBackwardsSearch range:NSMakeRange(0, self.session.wordStartLocation)];
            if(newLineRange.location == NSNotFound) {
                return NO;
            }
            
            // See if the current line has a switch statement
			NSString *regPattern = [[SCXcodeSwitchExpander sharedSwitchExpander] isSwift] ? @"\\s+switch\\s*" : @"\\s+switch\\s*\\\(";
			NSRange switchRange = [textView.string rangeOfString:regPattern options:NSRegularExpressionSearch range:NSMakeRange(newLineRange.location, self.session.wordStartLocation - newLineRange.location)];
            if(switchRange.location == NSNotFound) {
                return NO;
            }
            
            // Insert the selected autocomplete item
            [self.session insertCurrentCompletion];
			
            // Fetch the opening bracket for that switch statement
            NSUInteger openingBracketLocation = [textView.string rangeOfString:@"{" options:0 range:NSMakeRange(self.session.wordStartLocation, textView.string.length - self.session.wordStartLocation)].location;
			if(openingBracketLocation == NSNotFound) {
                return NO;
            }
			
			// Check if it's the opening bracket for the switch statement or something else
			NSString *remainingText = [textView.string substringWithRange:NSMakeRange(switchRange.location + switchRange.length, openingBracketLocation - switchRange.location - switchRange.length)];
			if([remainingText rangeOfString:@"}"].location != NSNotFound) {
				return NO;
			}
			
			NSRange selectedRange = textView.selectedRange;
			
            // Fetch the closing bracket for that switch statement
			NSUInteger closingBracketLocation = [self matchingBracketLocationForOpeningBracketLocation:openingBracketLocation
																							  inString:textView.string];
            if(closingBracketLocation == NSNotFound) {
                return NO;
            }
			
            NSRange defaultAutocompletionRange;
            // Get rid of the default autocompletion if necessary
            if ([[SCXcodeSwitchExpander sharedSwitchExpander] isSwift]) {
                defaultAutocompletionRange = [textView.string rangeOfString:@"\\s*case .<#constant#>:\\s*<#statements#>\\s*break\\s*default:\\s*break\\s*" options:NSRegularExpressionSearch range:NSMakeRange(openingBracketLocation, closingBracketLocation - openingBracketLocation)];
            } else {
                defaultAutocompletionRange = [textView.string rangeOfString:@"\\s*case <#constant#>:\\s*<#statements#>\\s*break;\\s*default:\\s*break;\\s*" options:NSRegularExpressionSearch range:NSMakeRange(openingBracketLocation, closingBracketLocation - openingBracketLocation)];
            }
			
            if(defaultAutocompletionRange.location != NSNotFound) {
                [textView insertText:@"" replacementRange:defaultAutocompletionRange];
				closingBracketLocation -= defaultAutocompletionRange.length;
            }
			
			NSRange switchContentRange = NSMakeRange(openingBracketLocation + 1, closingBracketLocation - openingBracketLocation - 1);
			NSString *switchContent = [textView.string substringWithRange:switchContentRange];
			
            // Generate the items to insert and insert them at the end
            NSMutableString *replacementString = [NSMutableString string];
			
			NSString *trimmedContent = [switchContent stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

			if(trimmedContent.length == 0) {
				// remove extraneous empty lines if existing content is only whitespace
				if (switchContent.length > 0) {
					[textView insertText:@"" replacementRange:switchContentRange];
					closingBracketLocation -= switchContent.length;
					switchContentRange.length = 0;
					[replacementString appendString:@"\n"];
				} else {
					// keep Swift code compact
					if (![[SCXcodeSwitchExpander sharedSwitchExpander] isSwift]) {
						[replacementString appendString:@"\n"];
					}
				}
			}
			
            for(IDEIndexSymbol *child in [((IDEIndexContainerSymbol*)symbol).children allObjects]) {

                // skip the `child` symbol if it is not a enum constant.
                if (![self isSymbolKindEnumConstant:child.symbolKind])
                {
                    continue;
                }
                
                if([switchContent rangeOfString:child.displayName].location == NSNotFound) {
                    if ([[SCXcodeSwitchExpander sharedSwitchExpander] isSwift]) {
                        NSString *childDisplayName = [self correctEnumConstantIfFromCocoa:[NSString stringWithFormat:@"%@",symbol] symbolName:symbolName cocoaEnumName:child.displayName];
                        [replacementString appendString:[NSString stringWithFormat:@"case .%@: \n<#statement#>\n", childDisplayName]];
                    } else {
                        [replacementString appendString:[NSString stringWithFormat:@"case %@: {\n<#statement#>\nbreak;\n}\n", child.displayName]];
                    }
                }
            }
			
            [textView insertText:replacementString replacementRange:NSMakeRange(switchContentRange.location + switchContentRange.length, 0)];
			
			closingBracketLocation += replacementString.length;
			switchContentRange = NSMakeRange(openingBracketLocation + 1, closingBracketLocation - openingBracketLocation - 1);
			switchContent = [textView.string substringWithRange:switchContentRange];
			
//          // Insert the default case if necessary
//          if([switchContent rangeOfString:@"default"].location == NSNotFound) {
//              if ([[SCXcodeSwitchExpander sharedSwitchExpander] isSwift]) {
//                  replacementString = [NSMutableString stringWithString:@"default: \nbreak\n\n"];
//              } else {
//                  replacementString = [NSMutableString stringWithString:@"default: {\nbreak;\n}\n"];
//              }
//              [textView insertText:replacementString replacementRange:NSMakeRange(switchContentRange.location + switchContentRange.length, 0)];
//              closingBracketLocation += replacementString.length;
//          }
            
            // Re-indent everything
			NSRange reindentRange = NSMakeRange(openingBracketLocation, closingBracketLocation - openingBracketLocation + 2);
            [textView _indentInsertedTextIfNecessaryAtRange:reindentRange];
			
			// Preserve the selected range
			[textView setSelectedRange:selectedRange];
			
			return YES;
        }
        
        break;
    }
	
	return NO;
}

- (NSString *)correctEnumConstantIfFromCocoa:(NSString *)symbol symbolName:(NSString *)symbolName cocoaEnumName:(NSString *)enumName
{
	if ([symbol rangeOfString:@"c:@E@"].location != NSNotFound) {
		return [enumName stringByReplacingOccurrencesOfString:symbolName withString:@""];
	}
	
	return enumName;
}

- (BOOL)isSymbolKindEnum:(DVTSourceCodeSymbolKind *)symbol
{
	return [symbol.identifier isEqualToString:@"Xcode.SourceCodeSymbolKind.Enum"];
}

- (BOOL)isSymbolKindEnumConstant:(DVTSourceCodeSymbolKind *)symbolKind
{
    return [symbolKind.identifier isEqualToString:@"Xcode.SourceCodeSymbolKind.EnumConstant"];
}

- (NSUInteger)matchingBracketLocationForOpeningBracketLocation:(NSUInteger)location inString:(NSString *)string
{
	if(string.length == 0) {
		return NSNotFound;
	}
    
    NSInteger matchingLocation = location;
    NSInteger counter = 1;
    while (counter > 0) {
        matchingLocation ++;
        
        if(matchingLocation == string.length - 1) {
            return NSNotFound;
        }
        
        NSString *character = [string substringWithRange:NSMakeRange(matchingLocation, 1)];
        
		if ([character isEqualToString:@"{"]) {
            counter++;
        }
        else if ([character isEqualToString:@"}"]) {
            counter--;
        }
    }
    
    return matchingLocation;
}

@end
