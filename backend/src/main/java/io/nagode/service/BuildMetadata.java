package io.nagode.service;
public record BuildMetadata(String name,String version){public static BuildMetadata current(){return new BuildMetadata("Nagode.io","1.0.0");}}
