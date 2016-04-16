//
//  DVTSourceCodeLanguage+SCXCodeSwitchExpander.m
//  SCXcodeSwitchExpander
//
//  Created by Tomohiro Kumagai on 4/11/16.
//  Copyright © 2016 Stefan Ceriu. All rights reserved.
//

#import "DVTSourceCodeLanguage+SCXCodeSwitchExpander.h"

@implementation DVTSourceCodeLanguage (SCXCodeSwitchExpander)

- (DVTSourceCodeLanguageKind)switchExpander_sourceCodeLanguageKind
{
    if ([self.languageName isEqualToString:@"Objective-C"]) {
        return DVTSourceCodeLanguageKindObjectiveC;
    }
    else if ([self.languageName isEqualToString:@"Swift"]) {
        return DVTSourceCodeLanguageKindSwift;
    }

    return DVTSourceCodeLanguageKindOther;
}

@end
