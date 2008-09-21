/*
 * CPKeyValueCoding.j
 * Foundation
 *
 * Created by Francisco Tolmasky.
 * Copyright 2008, 280 North, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

import "CPArray.j"
import "CPDictionary.j"
import "CPObject.j"

@implementation CPObject (KeyValueObserving)

- (void)willChangeValueForKey:(CPString)aKey
{

}


- (void)didChangeValueForKey:(CPString)aKey
{

}

- addObserver:(id)anObserver forKeyPath:(CPString)aPath options:(unsigned)options context:(id)aContext
{
    if (!anObserver || !aPath) 
        return;

    [[_CPKVOProxy proxyForObject:self] _addObserver:anObserver forKeyPath:aPath options:options context:aContext];
}

- removeObserver:(id)anObserver forKeyPath:(CPString)aPath
{
    if (!anObserver || !aPath) 
        return;

    [[KVOProxyMap objectForKey:[self hash]] _removeObserver:anObserver forKeyPath:aPath];
}

- (BOOL)automaticallyNotifiesObserversForKey:(CPString)aKey
{
    return YES;
}

@end

var KVOProxyMap = [CPDictionary dictionary];

//rule of thumb: _ methods are called on the real proxy object, others are called on the "fake" proxy object (aka the real object)

@implementation _CPKVOProxy : CPObject
{
    id              _targetObject;
    Class           _nativeClass;
    CPDictionary    _observerInfos;
    CPDictionary    _replacementMethods;
}

+ (id)proxyForObject:(CPObject)anObject
{
    var proxy = [KVOProxyMap objectForKey:[anObject hash]];

    if (proxy)
        return proxy;

    proxy = [[self alloc] initWithTarget:anObject];
    
    [proxy _replaceSetters];
    
    anObject.isa = proxy.isa;

    [KVOProxyMap setObject:proxy forKey:[anObject hash]];

    return proxy;
}

- (id)initWithTarget:(id)aTarget
{
    self = [super init];
    
    _targetObject       = aTarget;
    _nativeClass        = [aTarget class];
    _observerInfos      = [CPDictionary dictionary];
    _replacementMethods = [CPDictionary dictionary];
    
    return self;
}

- (void)_replaceSetters
{
    var currentClass = [_targetObject class];
        
    while (currentClass && currentClass != currentClass.super_class)
    {
        var methodList = currentClass.method_list,
            count = methodList.length;
            
        for (var i=0; i<count; i++)
        {
            var newMethod = _kvoMethodForMethod(methodList[i]);

            if (newMethod)
                [_replacementMethods setObject:newMethod forKey:methodList[i].name];
        }
        
        currentClass = currentClass.super_class;
    }
}

- (id)class
{
    return [KVOProxyMap objectForKey:[self hash]]._nativeClass;
}

- (BOOL)respondsToSelector:(SEL)aSelector
{
    var proxy = [_CPKVOProxy proxyForObject:self],
        imp = class_getInstanceMethod(proxy._nativeClass, aSelector);
        
    return imp ? YES : NO;
}

- (id)methodSignatureForSelector:(SEL)aSelector
{
    //FIXME: this only works because we don't have method signatures
    return [self respondsToSelector:aSelector];
}

- (IMP)methodForSelector:(SEL)aSelector
{
    var proxy = [_CPKVOProxy proxyForObject:self],
        imp = class_getInstanceMethod(proxy._nativeClass, aSelector),
        replacement = [proxy._replacementMethods objectForKey:aSelector];

    return replacement ? replacement : imp;
}

- (void)forwardInvocation:(CPInvocation)anInvocation
{
    var proxy = [_CPKVOProxy proxyForObject:self],
        method = [self methodForSelector:[anInvocation selector]];

    if (method)
        method.apply(self, anInvocation._arguments); //FIXME
    else
        [super forwardInvocation:anInvocation];
}

- (void)_addObserver:(id)anObserver forKeyPath:(CPString)aPath options:(unsigned)options context:(id)aContext
{
    if (!anObserver)
        return;

    var info = [_observerInfos objectForKey:[anObserver hash]];
    
    if (!info)
    {
        info = _CPKVOInfoMake(anObserver);
        [_observerInfos setObject:info forKey:[anObserver hash]];
    }

    if (aPath.indexOf('.') != CPNotFound)
        return print("WHOA, don't go crazy...");
    else
        [info.keyPaths setObject:_CPKVOInfoRecordMake(options, aContext) forKey:aPath];
}

- (void)_removeObserver:(id)anObserver forKeyPath:(CPString)aPath
{        
    var info = [_observerInfos objectForKey:[anObserver hash]],
        path = [info.keyPaths objectForKey:aPath];
    
    if (path)
        [info.keyPaths removeObjectForKey:aPath];
    
    if (![info.keyPaths count])
        [_observerInfos removeObjectForKey:anObserver];

    if (![_observerInfos count])
    {
        _targetObject.isa = _nativeClass; //restore the original class
        [KVOProxyMap removeObjectForKey:[_targetObject hash]];
    }
}

- (void)willChangeValueForKey:(CPString)aKey
{
    print("WILL CHANGE FOR: "+aKey);
}


- (void)didChangeValueForKey:(CPString)aKey
{
    print("DID CHANGE FOR: "+aKey);
}

@end

var _CPKVOInfoMake = function _CPKVOInfoMake(anObserver)
{
    return {
        observer: anObserver, 
        keyPaths: [CPDictionary dictionary],
        changes:  [CPDictionary dictionary]
    };
}

var _CPKVOInfoRecordMake = function _CPKVOInfoRecordMake(theOptions, aContext)
{
    return {
        options: theOptions ? theOptions : 0,
        context: aContext ? aContext : [CPNull null]
    };
}

var _kvoMethodForMethod = function _kvoMethodForMethod(theMethod)
{
    var methodName = theMethod.name,
        methodImplementation = theMethod.method_imp,
        setterKey = kvoKeyForSetter(methodName);
    
    if (setterKey)
    {
        var newMethodImp = function(self) 
        {
            [self willChangeValueForKey:setterKey];
            methodImplementation.apply(self, arguments);
            [self didChangeValueForKey:setterKey];
        }
        
        return newMethodImp;
    }

    return nil;
}

var kvoKeyForSetter = function kvoKeyForSetter(selector)
{
    if (selector.split(":").length > 2 || !([selector hasPrefix:@"set"] || [selector hasPrefix:@"_set"]))
        return nil;
        
    var keyIndex = selector.indexOf("set") + "set".length,
        colonIndex = selector.indexOf(":");
    
    return selector.charAt(keyIndex).toLowerCase() + selector.substring(keyIndex+1, colonIndex);
}
